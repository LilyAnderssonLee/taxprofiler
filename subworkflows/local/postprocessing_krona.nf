//
// Remove host reads via alignment and export off-target reads
//

include { KRAKENTOOLS_KREPORT2KRONA                } from '../../modules/nf-core/modules/krakentools/kreport2krona/main'
include { KRONA_CLEANUP as KRONA_KRAKENCLEANUP     } from '../../modules/local/krona_cleanup'
include { KRONA_KTIMPORTTEXT                       } from '../../modules/nf-core/modules/krona/ktimporttext/main'
include { CENTRIFUGE_KREPORT                       } from '../../modules/nf-core/modules/centrifuge/kreport/main'

workflow POSTPROCESSING_KRONA {
    take:
    krona_input
    databases

    main:
    ch_versions               = Channel.empty()
    ch_input_for_ktimporttext = Channel.empty()

    ch_files_for_krona = krona_input
        .branch {
            // malt:
            kraken2: it[0]['tool'] == 'kraken2'
            centrifuge:  it[0]['tool'] == 'centrifuge'
            //metaphlan3:
            //kaiju:
            //diamond:
        }

    ch_databases = databases
        .branch{
            centrifuge: it[0]['tool'] == 'centrifuge'
        }

    // TODO PUSH BACK CENTRIFUGE_KREPORT TO PROFILING.NF WHERE DATABASE ALREADY IS?
    ch_input_for_centrifuge_kreport = ch_files_for_krona.centrifuge
                                        .map{
                                            meta, file ->
                                                def db_meta     = [ tool: meta.tool, db_name: meta.db_name, db_params: meta.db_params ]
                                                def kfile        = file
                                                def sample_meta = [ id: meta.id, run_accession: meta.run_accession, instrument_platform: meta.instrument_platform, single_end: meta.single_end, is_fasta: meta.is_fasta ]
                                            [ db_meta, kfile, sample_meta ]
                                        }
                                        .dump(tag: "sample")


    ch_input_for_centrifuge_krona = ch_databases.centrifuge
                                        .collect()
                                        .dump(tag: "db")
                                        .combine(ch_input_for_centrifuge_kreport, by: 0)
                                        .dump(tag: "sm")

    // Kraken
    KRAKENTOOLS_KREPORT2KRONA ( ch_files_for_krona.kraken2 )
    KRONA_KRAKENCLEANUP ( KRAKENTOOLS_KREPORT2KRONA.out.txt )
    ch_kraken_for_krona = KRONA_KRAKENCLEANUP.out.txt
                            .map{
                                    [[id: it[0].tool + "-" + it[0].db_name, db_name: it[0].db_name, tool: it[0].tool ], it[1]]
                                }
                                .groupTuple()
    ch_input_for_ktimporttext = ch_input_for_ktimporttext.mix( ch_kraken_for_krona )
    ch_versions               = ch_versions.mix( KRAKENTOOLS_KREPORT2KRONA.out.versions.first() )
    ch_versions               = ch_versions.mix( KRONA_KRAKENCLEANUP.out.versions.first() )


    KRONA_KTIMPORTTEXT (ch_input_for_ktimporttext)

    ch_versions        = ch_versions.mix( KRONA_KTIMPORTTEXT.out.versions.first() )

    // Centrifuge
    //CENTRIFUGE_KREPORT (krona_input.centrifuge, ch_input_for_centrifuge.db)
    // ch_versions        = ch_versions.mix( /CENTRIFUGE_KREPORT.out.versions.first() )

    emit:
    versions       = ch_versions                 // channel: [ versions.yml ]
}

