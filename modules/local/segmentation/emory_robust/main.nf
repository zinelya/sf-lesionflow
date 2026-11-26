process SEGMENTATION_EMORY_ROBUST {
    tag "$meta.id"
    label 'process_gpu'
    container 'emorycn2l/emory_robust_wmh:v1.2'

    input:
    tuple val(meta), path(t1_mni), path(flair_mni)

    output:
    tuple val(meta), path("${meta.id}_emory_robust_binary.nii.gz"), emit: binary_mask
    tuple val(meta), path("${meta.id}_emory_robust_prob.nii.gz")  , emit: probability_map
    path "versions.yml"                                           , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def use_gpu  = task.ext.gpu
    def gpu_flag = use_gpu ? "--gpu" : ""
    """
    export OMP_NUM_THREADS=4
    export PATH=/opt/conda/envs/nnunet/bin:/opt/conda/bin:\$PATH
    export TORCH_HOME="\$(pwd)/.cache/torch"
    export MPLCONFIGDIR="\$(pwd)/.cache/matplotlib"
    export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True

    bash /app/main.sh -t \$(realpath ${t1_mni}) -f \$(realpath ${flair_mni}) -o \$(realpath ${meta.id}_emory_robust_binary.nii.gz) --no-n4 --no-coreg ${gpu_flag}

    nnunet_probs_to_nifti.py --npz .app_outputs/2d/wmh.npz .app_outputs/3d_fullres/wmh.npz \
                             --ref .app_inputs/wmh_0001.nii.gz \
                             --output ${meta.id}_emory_robust_prob.nii.gz \
                             --check_mask ${meta.id}_emory_robust_binary.nii.gz

    rm -rf .app_inputs .app_outputs

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        emory_robust_wmh: 1.2
    END_VERSIONS
    """
    stub:
    """
    touch ${meta.id}_emory_robust_binary.nii.gz
    touch ${meta.id}_emory_robust_prob.nii.gz
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        emory_robust_wmh: 1.2
    END_VERSIONS
    """
}
