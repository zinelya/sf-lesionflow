// Phase 3 Subworkflow: STAPLE Consensus Fusion
//
// Groups all per-algorithm BIDS-labelled binary masks for each session,
// then runs CONSENSUS_STAPLE once per session.

include { CONSENSUS_STAPLE } from '../../modules/local/consensus/staple/main'

workflow CONSENSUS {
    take:
    ch_flair_mni         // [meta, flair_mni]  — reference image for STAPLE grid
    ch_all_binary_masks  // [meta, [sorted_mask_list]]

    main:

    ch_staple_input = ch_flair_mni
        .join(ch_all_binary_masks)
    // Result: [meta, flair_mni, [sorted_masks]]  → matches CONSENSUS_STAPLE input

    CONSENSUS_STAPLE(ch_staple_input)

    emit:
    staple_probmap       = CONSENSUS_STAPLE.out.staple_probmap
    staple_thr90_binary  = CONSENSUS_STAPLE.out.staple_thr90_binary
    staple_thr90_labels  = CONSENSUS_STAPLE.out.staple_thr90_labels
    versions             = CONSENSUS_STAPLE.out.versions
}
