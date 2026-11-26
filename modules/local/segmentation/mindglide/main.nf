process SEGMENTATION_MINDGLIDE {
    tag "$meta.id"
    label 'process_gpu'
    container 'frheault/sf-lesionflow-mindglide:1.0.0'

    input:
    tuple val(meta), path(flair)

    output:
    tuple val(meta), path("mindglide.nii.gz")     , emit: binary_mask
    tuple val(meta), path("mindglide_prob.nii.gz"), emit: probability_map
    path "versions.yml"                           , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def label_id = task.ext.label_id ?: 18
    def device   = task.ext.gpu ? "cuda" : "cpu"
    """
    export HF_HUB_OFFLINE=1
    export TORCH_HOME="\$(pwd)/.cache/torch"
    export MPLCONFIGDIR="\$(pwd)/.cache/matplotlib"

    # mindglide_prob.py == `mindglide`, plus the lesion-channel softmax (argmaxed and
    # discarded upstream) saved as multiclass_prob.nii.gz -- see its docstring.
    MINDGLIDE_PROB_LABEL=${label_id} mindglide_prob.py -i ${flair} -o multiclass.nii.gz --device ${device}

    conform_synthseg.py --input multiclass.nii.gz --ref ${flair} --output mindglide.nii.gz --label_id ${label_id}
    conform_synthseg.py --input multiclass_prob.nii.gz --ref ${flair} --output mindglide_prob.nii.gz --continuous
    rm -f multiclass.nii.gz multiclass_prob.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mindglide: 1.3.0
    END_VERSIONS
    """

    stub:
    """
    touch mindglide.nii.gz
    touch mindglide_prob.nii.gz
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mindglide: 1.3.0
    END_VERSIONS
    """
}
