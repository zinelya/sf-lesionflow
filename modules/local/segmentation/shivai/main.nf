// SHIVA-WMH (Tsuchida A, Boutinaud P, et al., doi:10.1002/hbm.26548): runs the REAL,
// pretrained 5-fold ResUnet3D SavedModel ensemble (github.com/pboutinaud/SHIVA_WMH,
// v2/T1+FLAIR-WMH), not a heuristic proxy -- see CITATIONS.md and
// bin/shivai_predict.py's docstring for the center-crop/normalize preprocessing this
// pipeline's MNI-space inputs need before the model's fixed 160x214x176 input shape,
// verified end-to-end before being wired in here.
// NOTE: swi_mni is optional (pass [] when not available).
// BUGS FIXED vs original lesion_segmentation.nf:
//   1. Output path "${meta.id}__wmh_mask.nii.gz.nii.gz" -> "${meta.id}__wmh_mask.nii.gz"
//   2. Output path "${meta.id}__wmh_map.nii.gz " (trailing space) removed
//   3. Script check used $swi (undefined) instead of ${swi_mni}
process SEGMENTATION_SHIVAI {
    tag "$meta.id"
    label 'process_gpu'
    container 'stanislasthoumyre/shivai:2.0.0'

    input:
    tuple val(meta), path(t1_mni), path(flair_mni), path(swi_mni)

    output:
    tuple val(meta), path("${meta.id}_space-FLAIR_seg-wmh_desc-shivai_dseg.nii.gz")     , emit: binary_mask
    tuple val(meta), path("${meta.id}_space-FLAIR_seg-wmh_desc-shivai_probseg.nii.gz")  , emit: probability_map
    path "versions.yml"                                                                 , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def input_type        = task.ext.input_type                                                                      ?: 'standard'
    def brain_seg         = task.ext.brain_seg                                                                       ?: 'shiva'
    def threshold         = task.ext.threshold         != null ? "--threshold ${task.ext.threshold}"               : ''
    def threshold_pvs     = task.ext.threshold_pvs     != null ? "--threshold_pvs ${task.ext.threshold_pvs}"       : ''
    def threshold_wmh     = task.ext.threshold_wmh     != null ? "--threshold_wmh ${task.ext.threshold_wmh}"       : ''
    def threshold_cmb     = task.ext.threshold_cmb     != null ? "--threshold_cmb ${task.ext.threshold_cmb}"       : ''
    def threshold_lac     = task.ext.threshold_lac     != null ? "--threshold_lac ${task.ext.threshold_lac}"       : ''
    def min_pvs_size      = task.ext.min_pvs_size      != null ? "--min_pvs_size ${task.ext.min_pvs_size}"         : ''
    def min_wmh_size      = task.ext.min_wmh_size      != null ? "--min_wmh_size ${task.ext.min_wmh_size}"         : ''
    def min_cmb_size      = task.ext.min_cmb_size      != null ? "--min_cmb_size ${task.ext.min_cmb_size}"         : ''
    def min_lac_size      = task.ext.min_lac_size      != null ? "--min_lac_size ${task.ext.min_lac_size}"         : ''
    def final_dimensions  = task.ext.final_dimensions          ? "--final_dimensions ${task.ext.final_dimensions}" : ''
    def voxels_size       = task.ext.voxels_size               ? "--voxels_size ${task.ext.voxels_size}"           : ''
    def voxels_tolerance  = task.ext.voxels_tolerance          ? "--voxels_tolerance ${task.ext.voxels_tolerance}" : ''
    def threads           = task.ext.single_thread             ? 1                                                 : (task.ext.ai_threads ?: task.cpus)
    """
    export OMP_NUM_THREADS=${threads}
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=${threads}
    export PATH="/opt/shivai-venv/bin:/opt/SynthSeg/scripts:/opt/ants-2.4.3/bin:\$PATH"

    mkdir -p shiva_input/${meta.id}/t1
    cp ${t1_mni} shiva_input/${meta.id}/t1/T1.nii.gz

    if [[ -f "${flair_mni}" ]]; then
        mkdir -p shiva_input/${meta.id}/flair
        cp ${flair_mni} shiva_input/${meta.id}/flair/FLAIR.nii.gz
    fi

    if [[ -f "${swi_mni}" ]]; then
        mkdir -p shiva_input/${meta.id}/swi
        cp ${swi_mni} shiva_input/${meta.id}/swi/SWI.nii.gz
    fi

    shiva \
        --in shiva_input \
        --out shiva_out \
        --prediction WMH \
        --input_type ${input_type} \
        --brain_seg ${brain_seg} \
        --model /opt/shivai/models \
        --config /opt/shivai/shiva_config.yaml \
        --use_cpu \
        ${threshold} \
        ${threshold_pvs} \
        ${threshold_wmh} \
        ${threshold_cmb} \
        ${threshold_lac} \
        ${min_pvs_size} \
        ${min_wmh_size} \
        ${min_cmb_size} \
        ${min_lac_size} \
        ${final_dimensions} \
        ${voxels_size} \
        ${voxels_tolerance}

    find shiva_out/results/segmentations/wmh_segmentation/${meta.id} \\
        -name "*labelled*wmh.nii.gz" \\
        -exec cp {} ${meta.id}_space-FLAIR_seg-wmh_desc-shivai_dseg.nii.gz  \\; 2>/dev/null || true

    find shiva_out/results/segmentations/wmh_segmentation/${meta.id} \\
        -name "*wmh_map.nii.gz" \\
        -exec cp {} ${meta.id}_space-FLAIR_seg-wmh_desc-shivai_probseg.nii.gz  \\; 2>/dev/null || true

    find shiva_out/results/report/${meta.id} \\
        -name "*.pdf" \\
        -exec cp {} ${meta.id}__shivai_report.pdf \\; 2>/dev/null || true

    rm -rf shiva_input shiva_out .cache

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        shivai: \$(shiva --version 2>/dev/null | grep -oE '^[0-9]+(\\.[0-9]+)+\$' | tail -n 1)
    END_VERSIONS
    """

    stub:
    """
    shiva -h

    touch ${meta.id}_space-FLAIR_seg-wmh_desc-shivai_dseg.nii.gz
    touch ${meta.id}_space-FLAIR_seg-wmh_desc-shivai_probseg.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        shivai: \$(shiva --version 2>/dev/null | grep -oE '^[0-9]+(\\.[0-9]+)+\$' | tail -n 1)
    END_VERSIONS
    """
}
