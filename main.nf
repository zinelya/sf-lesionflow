#!/usr/bin/env nextflow

def helpMessage() {
    log.info"""
    ================================================================================
    Multiple Sclerosis Lesion Segmentation Pipeline (sf-lesionflow) v${workflow.manifest.version}
    ================================================================================

    Usage:
    nextflow run main.nf --input /path/to/bids_dataset \\
                         --mni_template /path/to/mni_masked.nii.gz \\
                         --fs_license /path/to/license.txt \\
                         -profile docker -resume

    Mandatory arguments:
      --input [path]                Input directory containing BIDS subjects (sub-*/ses-*/anat/*).
      --mni_template [path]         Path to standard MNI reference template (nii.gz).
      --fs_license [path]           Path to FreeSurfer license file (required for SAMSEG).

    Optional arguments:
      --participant_label [str]     Filter subjects by comma-separated IDs (e.g. 'sub-001,sub-002').
      --output [path]               Directory to publish results (default: '${params.output}').
      --algorithms [str]            Comma-separated allow-list of algorithms to run (e.g. 'lst_ai,samseg').
                                    Valid options: ${AlgorithmSelection.ALL.join(', ')}.
      --skip_algorithms [str]       Comma-separated deny-list of algorithms to skip (e.g. 'emory_robust').
      --max_memory [str]            Warn about algorithms exceeding this memory limit (e.g. '20.GB').
      --staple_threshold [float]    STAPLE consensus probability threshold (default: 0.90).
      --staple_min_cluster_size [int] Minimum lesion cluster size in voxels/mm3 (default: 6).
      --staple_min_distance [int]   Minimum peak distance for watershed instances (default: 3).
      --staple_gaussian_sigma [float] Gaussian smoothing sigma for distance transform (default: 0.8).
      --pct_change_threshold [float] Percentage volume change threshold for trajectory status (default: 20.0).
      --lesion_brainmask [str]      Brain-mask lesion predictions: 'unstripped' (algorithms fed images with skull,
                                    default), 'all' or 'none'.
      --lesion_brainmask_dilation [int] Brain mask dilation in voxels before masking (default: 1).
      --template_space [str]        BIDS space- label of the template grid (default: 'MNI').
      --publish_dir_mode [str]      Nextflow publishDir mode (default: 'symlink'; use 'copy' to archive results).
      --publish_intermediates [bool] Publish native-space preprocessing under ses-*/preproc/ (default: true).
      --publish_native [bool]       Also publish native-space lesion outputs under ses-*/native/ (default: false).
      --help                        Display this help message.
    """.stripIndent()
}

// Default parameters
params.input                     = false
params.mni_template              = false
params.fs_license                = false
params.participant_label         = false
params.output                    = "results"
params.help                      = false
params.algorithms                = false
params.skip_algorithms           = false
params.max_memory                = false
params.staple_threshold          = 0.90
params.staple_min_cluster_size   = 6
params.staple_min_distance       = 3
params.staple_gaussian_sigma     = 0.8
params.pct_change_threshold      = 20.0
params.lesion_brainmask          = 'unstripped'
params.lesion_brainmask_dilation = 1
params.template_space            = 'MNI'
params.publish_dir_mode          = 'symlink'
params.publish_intermediates     = true
params.publish_native            = false

// -----------------------------------------------------------------------------
// Subworkflow & Utility Imports
// -----------------------------------------------------------------------------
include { PREPROCESSING   } from './subworkflows/local/preprocessing'
include { SEGMENTATION    } from './subworkflows/local/segmentation'
include { CONSENSUS       } from './subworkflows/local/consensus'
include { HARMONIZATION   } from './subworkflows/local/harmonization'
include { QC_PIPELINE     } from './subworkflows/local/qc_pipeline'
include { PROBE_VERSIONS  } from './modules/local/probe_versions'

// -----------------------------------------------------------------------------
// Channel Ingestion Workflow
// -----------------------------------------------------------------------------
workflow get_data {
    main:
        if (!params.input) {
            error "Mandatory argument --input missing. Please provide the BIDS dataset directory."
        }
        if (!params.mni_template) {
            error "Mandatory argument --mni_template missing. Please provide the MNI reference template."
        }
        if (!params.fs_license) {
            error "Mandatory argument --fs_license missing. Please provide the FreeSurfer license file."
        }

        input_dir = file(params.input)

        def allowed_participants = params.participant_label
            ? (params.participant_label.toString().tokenize(',').collect { it.trim().replaceFirst('^sub-', '') } as Set)
            : null

        ch_t1 = Channel.fromPath("${input_dir}/sub-*/ses-*/anat/*T1w.nii.gz")
            .map { f ->
                def sid = f.parent.parent.parent.name
                def ses = f.parent.parent.name
                [ [id: "${sid}_${ses}", subject: sid, session: ses], f ]
            }
            .filter { meta, f ->
                !allowed_participants || allowed_participants.contains(meta.subject.replaceFirst('^sub-', ''))
            }
            .ifEmpty { error "No T1w files found in ${input_dir} matching sub-*/ses-*/anat/*T1w.nii.gz${params.participant_label ? " for participant(s): ${params.participant_label}" : ''}" }

        ch_flair = Channel.fromPath("${input_dir}/sub-*/ses-*/anat/*FLAIR.nii.gz")
            .map { f ->
                def sid = f.parent.parent.parent.name
                def ses = f.parent.parent.name
                [ [id: "${sid}_${ses}", subject: sid, session: ses], f ]
            }
            .filter { meta, f ->
                !allowed_participants || allowed_participants.contains(meta.subject.replaceFirst('^sub-', ''))
            }
            .ifEmpty { error "No FLAIR files found in ${input_dir} matching sub-*/ses-*/anat/*FLAIR.nii.gz${params.participant_label ? " for participant(s): ${params.participant_label}" : ''}" }

        ch_mni_template = Channel.fromPath(params.mni_template, checkIfExists: true)
        ch_fs_license   = Channel.fromPath(params.fs_license, checkIfExists: true)

    emit:
        t1           = ch_t1
        flair        = ch_flair
        mni_template = ch_mni_template
        fs_license   = ch_fs_license
}

// -----------------------------------------------------------------------------
// Main Pipeline Execution DAG
// -----------------------------------------------------------------------------
workflow {
    // ── Moved from top-level (NF 26.x forbids bare statements outside workflow) ──
    if (params.help) {
        helpMessage()
        exit 0
    }

    // active_algorithms resolved once at parse-time; used by groupTuple(size:)
    // further below — must stay a plain List, never a channel value.
    def active_algorithms = AlgorithmSelection.resolveActive(params)
    log.info "Active segmentation algorithms (${active_algorithms.size()}/${AlgorithmSelection.ALL.size()}): ${active_algorithms.join(', ')}"
    if (active_algorithms.size() == 1) {
        log.warn "Only one algorithm active (${active_algorithms[0]}) -- CONSENSUS_STAPLE will degenerate to that single mask, not a real consensus."
    }

    def ALGORITHM_MEMORY_GB = [
        lst_ai: 8, samseg: 16, wmh_synthseg: 16, fast_outlier: 8, flames: 8,
        truenet: 16, hypermapp3r: 16, segcsvd: 8, emory_robust: 16, mars_wmh: 8,
        bawil: 8, mimosa: 8, shivai: 8, mindglide: 8
    ]
    assert ALGORITHM_MEMORY_GB.keySet() == AlgorithmSelection.ALL as Set
    assert AlgorithmSelection.BIDS_LABEL.keySet() == AlgorithmSelection.ALL as Set
    assert AlgorithmSelection.UNSTRIPPED_INPUT.every { it in AlgorithmSelection.ALL }
    assert AlgorithmSelection.ALL.every { AlgorithmSelection.CONTAINER.containsKey(it) }
    def brainmask_targets = AlgorithmSelection.brainmaskTargets(params)
    log.info "Lesion brain masking (--lesion_brainmask ${params.lesion_brainmask}): ${(active_algorithms.intersect(brainmask_targets) ?: ['none']).join(', ')}"

    if (params.max_memory) {
        def max_gb = (params.max_memory as nextflow.util.MemoryUnit).toGiga()
        def oversized = active_algorithms.findAll { ALGORITHM_MEMORY_GB[it] > max_gb }
        if (oversized) {
            log.warn """\
            --max_memory ${params.max_memory} is below the declared requirement for:
            ${oversized.collect { "  - ${it} (~${ALGORITHM_MEMORY_GB[it]}GB)" }.join('\n')}
            These will likely fail or be OOM-killed under this limit.
            Exclude them with --skip_algorithms ${oversized.join(',')}, or raise --max_memory.
            """.stripIndent()
        }
    }

    data = get_data()

    // =========================================================================
    // PHASE 1 — Preprocessing, Coregistration & Standard-Space Projection
    // =========================================================================
    PREPROCESSING(
        data.t1,
        data.flair,
        data.mni_template
    )

    ch_mni_paired     = PREPROCESSING.out.t1_mni.join(PREPROCESSING.out.flair_mni)
    ch_mni_flair_only = PREPROCESSING.out.flair_mni
    ch_mni_unstripped = PREPROCESSING.out.t1_unstripped_mni.join(PREPROCESSING.out.flair_unstripped_mni)

    // =========================================================================
    // PHASE 2 — Independent Algorithm Execution
    // =========================================================================
    SEGMENTATION(
        ch_mni_paired,
        ch_mni_flair_only,
        ch_mni_unstripped,
        PREPROCESSING.out.flair_unstripped_mni,
        PREPROCESSING.out.t1_native_stripped,
        PREPROCESSING.out.flair_native_coregistered,
        PREPROCESSING.out.t1_pre_n4,
        PREPROCESSING.out.flair_pre_n4,
        PREPROCESSING.out.t1_native_unstripped,
        PREPROCESSING.out.flair_native_unstripped,
        PREPROCESSING.out.flair_native_full_fov,
        PREPROCESSING.out.flair_synthstrip_mask,
        PREPROCESSING.out.flair_native_unstripped_crop,
        PREPROCESSING.out.session_transforms,
        data.mni_template,
        data.fs_license,
        PREPROCESSING.out.brainmask_mni
    )

    // Group per-algorithm masks deterministically so STAPLE input order is stable.
    // active_algorithms is a parse-time Groovy List — groupTuple(size:) requires a
    // plain integer, not a channel value, hence groupSorted lives here, not in the
    // SEGMENTATION subworkflow. See nextflow-io/nextflow#1702.
    def groupSorted = { ch ->
        ch.map { meta, algo, f -> [meta, f] }
          .groupTuple(by: 0, size: active_algorithms.size())
          .map { meta, files -> [meta, files.sort { it.name }] }
    }
    ch_all_binary_masks = groupSorted.call(SEGMENTATION.out.lesion_finalize_masks)
    ch_all_sidecars     = groupSorted.call(SEGMENTATION.out.lesion_finalize_sidecars)

    // =========================================================================
    // PHASE 3 — STAPLE Consensus Fusion
    // =========================================================================
    CONSENSUS(
        ch_mni_flair_only,
        ch_all_binary_masks
    )

    // =========================================================================
    // PHASE 4 — Longitudinal Harmonization
    // =========================================================================
    HARMONIZATION(
        CONSENSUS.out.staple_thr90_binary
    )

    // =========================================================================
    // PHASE 5 — Quality Control & MultiQC Reporting
    // =========================================================================
    def summary_html = "<dl>" +
        "<dt>Input</dt><dd>${params.input ?: ''}</dd>" +
        "<dt>Active Algorithms</dt><dd>" + active_algorithms.join(', ') + "</dd>" +
        "<dt>STAPLE Threshold</dt><dd>${params.staple_threshold}</dd>" +
        "<dt>Min Cluster Size</dt><dd>${params.staple_min_cluster_size}</dd>" +
        "<dt>Pct Change Threshold</dt><dd>${params.pct_change_threshold}</dd>" +
        "<dt>Lesion Brain Mask</dt><dd>${params.lesion_brainmask} (dilation ${params.lesion_brainmask_dilation} vox): ${active_algorithms.intersect(brainmask_targets).join(', ') ?: 'none'}</dd>" +
        "<dt>Volumes</dt><dd>MNI-normalized (template grid, affine normalization of the baseline T1w)</dd>" +
        "</dl>"

    def summary_yaml = """\
id: sf-lesionflow-summary
section_name: Workflow Parameters
plot_type: html
data: '${summary_html}'
"""
    ch_workflow_summary = Channel.value(summary_yaml)
        .collectFile(name: 'workflow_summary_mqc.yaml')

    ch_methods_desc = Channel.fromPath("${projectDir}/assets/methods_description_template.yml")
        .collectFile(name: 'methods_description_mqc.yaml')

    def probe_keys = active_algorithms.toList().sort() + (('segcsvd' in active_algorithms) ? ['synthseg'] : [])
    PROBE_VERSIONS(Channel.fromList(probe_keys))

    ch_software_versions = PROBE_VERSIONS.out.versions
        .mix(PREPROCESSING.out.versions)
        .mix(CONSENSUS.out.versions)
        .mix(HARMONIZATION.out.versions)
        .map { f -> f.text.trim() }
        .unique()

    ch_collated_versions = ch_software_versions
        .collectFile(name: 'collated_versions_mqc_versions.yml', newLine: true, sort: true)
    ch_software_versions
        .collectFile(name: 'software_versions.yml', newLine: true, sort: true,
                     storeDir: "${params.output}/pipeline_info")

    // Registration QC triples: [meta, fixed, warped, affine]
    ch_reg_flair_to_t1 = PREPROCESSING.out.t1_native_stripped
        .join(PREPROCESSING.out.flair_native_coregistered)
        .join(PREPROCESSING.out.reg_flair_to_t1_affine)

    ch_followup_base_t1 = PREPROCESSING.out.grouped_t1_meta
        .filter { meta, base_img, cur_img, is_base -> !is_base }
        .map { meta, base_img, cur_img, is_base -> [meta, base_img] }
    ch_reg_t1_to_baseline = ch_followup_base_t1
        .join(PREPROCESSING.out.reg_t1_to_baseline_warped)
        .join(PREPROCESSING.out.reg_t1_to_baseline_affine)

    ch_reg_t1_to_mni = PREPROCESSING.out.reg_baseline_to_mni_warped
        .combine(data.mni_template)
        .map { meta, warped_t1, mni -> [meta, mni, warped_t1] }
        .join(PREPROCESSING.out.reg_baseline_to_mni_affine)

    QC_PIPELINE(
        ch_mni_paired,
        ch_all_binary_masks,
        ch_all_sidecars,
        CONSENSUS.out.staple_thr90_binary,
        ch_reg_flair_to_t1,
        ch_reg_t1_to_baseline,
        ch_reg_t1_to_mni,
        HARMONIZATION.out.audit_csv,
        ch_collated_versions,
        ch_workflow_summary,
        ch_methods_desc
    )
}
