process SEGMENTATION_TRUENET {
    tag "$meta.id"
    label 'process_gpu'
    container 'frheault/sf-lesionflow-truenet:1.0.0'

    input:
    tuple val(meta), path(t1), path(flair)

    output:
    tuple val(meta), path("truenet.nii.gz")     , emit: binary_mask
    tuple val(meta), path("truenet_prob.nii.gz"), emit: probability_map, optional: true
    path "versions.yml"                         , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def threshold = task.ext.threshold ?: 0.5
    def use_gpu   = task.ext.gpu
    def cpu_arg   = use_gpu ? "False" : "True"
    """
    export TRUENET_PRETRAINED_MODEL_PATH=/opt/truenet_models
    export TORCH_HOME="\$(pwd)/.cache/torch"
    export MPLCONFIGDIR="\$(pwd)/.cache/matplotlib"
    mkdir -p out

    flair_path=\$(realpath ${flair} | head -n 1)
    t1_path=\$(realpath ${t1} | head -n 1)

    echo "FLAIR T1" > masterfile.txt
    echo "\$flair_path \$t1_path" >> masterfile.txt

    truenet apply -i masterfile.txt -m mwsc -o out -cpu ${cpu_arg}

    threshold_probmap.py --input_glob 'out/Predicted_probmap_truenet_*.nii.gz' \
                         --output truenet.nii.gz \
                         --threshold ${threshold}

    prob_file=\$(ls out/Predicted_probmap_truenet_*.nii.gz 2>/dev/null | head -n 1)
    if [ -n "\$prob_file" ]; then
        mv "\$prob_file" truenet_prob.nii.gz
    fi
    rm -rf masterfile.txt out

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        truenet: 1.0
    END_VERSIONS
    """

    stub:
    """
    touch truenet.nii.gz
    touch truenet_prob.nii.gz
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        truenet: 1.0
    END_VERSIONS
    """
}
