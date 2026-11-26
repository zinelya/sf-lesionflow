process SEGMENTATION_LST_AI {
    tag "$meta.id"
    label 'process_gpu'
    container 'frheault/sf-lesionflow-lst_ai:1.1.0'

    input:
    tuple val(meta), path(t1), path(flair)

    output:
    tuple val(meta), path("lst_ai.nii.gz")     , emit: binary_mask
    tuple val(meta), path("lst_ai_prob.nii.gz"), emit: probability_map
    path "versions.yml"                        , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def use_gpu = task.ext.gpu
    def device = use_gpu ? "0" : "cpu"
    """
    export CUDA_VISIBLE_DEVICES=${use_gpu ? '0' : '-1'}
    export TF_FORCE_GPU_ALLOW_GROWTH=true
    export TF_GPU_ALLOCATOR=cuda_malloc_async
    export TF_CPP_MIN_LOG_LEVEL=2
    export OMP_NUM_THREADS=${task.cpus}
    export PYTHONNOUSERSITE=1
    unset PYTHONPATH
    export TORCH_HOME="\$(pwd)/.cache/torch"
    export MPLCONFIGDIR="\$(pwd)/.cache/matplotlib"

    mkdir -p tmp_out
    lst_ai_prob.py --output_prob lst_ai_prob.nii.gz --work_dir lst_work \
        --t1 ${t1} --flair ${flair} --output tmp_out --segment_only --stripped --device ${device} --threads ${task.cpus}

    if [ -f "tmp_out/space-flair_seg-lst.nii.gz" ]; then
        mv tmp_out/space-flair_seg-lst.nii.gz lst_ai.nii.gz
    else
        echo "Error: LST-AI output missing" >&2
        exit 1
    fi
    rm -rf tmp_out lst_work

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        lst_ai: 2.0.0
    END_VERSIONS
    """

    stub:
    """
    touch lst_ai.nii.gz
    touch lst_ai_prob.nii.gz
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        lst_ai: 2.0.0
    END_VERSIONS
    """
}
