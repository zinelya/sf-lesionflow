process SEGMENTATION_MARS_WMH {
    tag "$meta.id"
    label 'process_gpu'
    container 'ghcr.io/miac-research/wmh-nnunet:1.0.2'

    input:
    tuple val(meta), path(t1_unstripped), path(flair_unstripped)

    output:
    tuple val(meta), path("mars_wmh.nii.gz")     , emit: binary_mask
    tuple val(meta), path("mars_wmh_prob.nii.gz"), emit: probability_map
    tuple val(meta), path("*_QC.html")           , emit: qc_html    , optional: true
    path "versions.yml"                          , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def use_gpu = task.ext.gpu
    def gpu_env = use_gpu ? "export CUDA_VISIBLE_DEVICES=0" : "export CUDA_VISIBLE_DEVICES=\"\""
    """
    export OMP_NUM_THREADS=${task.cpus}
    export PYTHONNOUSERSITE=1
    unset PYTHONPATH
    export TORCH_HOME="\$(pwd)/.cache/torch"
    export MPLCONFIGDIR="\$(pwd)/.cache/matplotlib"
    export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
    ${gpu_env}

    sed "s/-t Task700_WMH'/-t Task700_WMH -z'/" /opt/scripts/pipeline_nnunet.py > pipeline_nnunet_prob.py
    grep -q "Task700_WMH -z'" pipeline_nnunet_prob.py || { echo "Error: MARS-WMH nnUNet_predict call not found; cannot enable -z" >&2; exit 1; }

    PYTHONPATH=/opt/scripts python pipeline_nnunet_prob.py \
        --flair ${flair_unstripped} \
        --t1 ${t1_unstripped} \
        --fnOut mars_wmh.nii.gz \
        --overwrite \
        --debug

    mars_tmp=\$(ls -d mars_wmh_temp-* | head -n 1)
    nnunet_probs_to_nifti.py --npz \$mars_tmp/nnUNet/wmh.npz \
                             --ref \$mars_tmp/nnUNet/wmh_0000.nii.gz \
                             --target ${flair_unstripped} \
                             --output mars_wmh_prob.nii.gz \
                             --check_mask mars_wmh.nii.gz
    rm -rf "\$mars_tmp" pipeline_nnunet_prob.py

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mars_wmh: 1.0.2
    END_VERSIONS
    """

    stub:
    """
    touch mars_wmh.nii.gz
    touch mars_wmh_prob.nii.gz
    touch mars_wmh_QC.html
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mars_wmh: 1.0.2
    END_VERSIONS
    """
}
