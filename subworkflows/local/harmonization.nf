// Phase 4 Subworkflow: Longitudinal Harmonization & Tracking Audit Trail
//
// Groups per-session STAPLE consensus masks by subject, then runs
// HARMONIZATION_STAPLE once per subject across all their sessions.

include { HARMONIZATION_STAPLE } from '../../modules/local/harmonization/staple/main'

workflow HARMONIZATION {
    take:
    ch_staple_thr90_binary  // [meta, staple_thr90_binary.nii.gz]  — one per session

    main:

    ch_harmonize_input = ch_staple_thr90_binary
        .map { meta, bin_mask -> [meta.subject, meta, bin_mask] }
        .groupTuple(by: 0)
    // Result: [subject, [metas], [masks]]  → matches HARMONIZATION_STAPLE input

    HARMONIZATION_STAPLE(ch_harmonize_input)

    emit:
    harmonized_binary  = HARMONIZATION_STAPLE.out.harmonized_binary
    harmonized_labels  = HARMONIZATION_STAPLE.out.harmonized_labels
    audit_csv          = HARMONIZATION_STAPLE.out.audit_csv
    versions           = HARMONIZATION_STAPLE.out.versions
}
