// BAWIL (Bashiri Bawil M, et al., "Incorporating normal periventricular changes for
// enhanced pathological WMH segmentation: multiclass deep learning approaches,"
// Biomedical Engineering Online, 2026, PMC13202883): runs the REAL, pretrained
// Keras model (huggingface.co/Bawil/wmh_leverage_normal_abnormal_segmentation,
// scenario2_multiclass_model.h5) -- a 3-class U-Net (0: background, 1: normal WMH,
// 2: abnormal WMH) on axial FLAIR slices.
process SEGMENTATION_BAWIL {
    tag "$meta.id"
    label 'process_gpu'
    container 'frheault/sf-lesionflow-bawil:1.0.0'

    input:
    // 1 mm resampled, non-N4 FLAIR (full FOV) + its SynthStrip brain mask on the same grid
    tuple val(meta), path(flair), path(brainmask)

    output:
    tuple val(meta), path("bawil.nii.gz")     , emit: binary_mask
    tuple val(meta), path("bawil_prob.nii.gz"), emit: probability_map
    path "versions.yml"                       , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def framing      = task.ext.framing       ?: 'brainbox'
    def orientation  = task.ext.orientation   ?: 'rot90'
    def strip        = task.ext.strip != null ? task.ext.strip : true
    def fov_fill     = task.ext.fov_fill      ?: 0.92
    def slab_mm      = task.ext.slab_mm       != null ? task.ext.slab_mm : 0
    def decision     = task.ext.decision      ?: 'argmax'
    def prob_thresh  = task.ext.prob_threshold ?: 0.50
    def min_cluster  = task.ext.min_cluster_size ?: 3
    def use_gpu      = task.ext.gpu
    """
    export CUDA_VISIBLE_DEVICES=${use_gpu ? '0' : '-1'}
    export TF_CPP_MIN_LOG_LEVEL=2
    export MPLCONFIGDIR="\$(pwd)/.cache/matplotlib"

    bawil_filter.py --flair ${flair} \
                    --brainmask ${brainmask} \
                    --output bawil.nii.gz \
                    --output_prob bawil_prob.nii.gz \
                    --framing ${framing} \
                    ${strip ? '--strip' : ''} \
                    --orientation ${orientation} \
                    --fov_fill ${fov_fill} \
                    --slab_mm ${slab_mm} \
                    --decision ${decision} \
                    --prob_threshold ${prob_thresh} \
                    --min_cluster_size ${min_cluster}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        bawil: 1.0
    END_VERSIONS
    """

    stub:
    """
    touch bawil.nii.gz
    touch bawil_prob.nii.gz
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        bawil: 1.0
    END_VERSIONS
    """
}
