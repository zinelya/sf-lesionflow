// GPU disabled: the published image only has the CPU-only torch wheel baked in
// (dockerfiles/flames/Dockerfile installs torch from the CPU index), so
// `-device cuda` would fail nnU-Net's torch.cuda.is_available() check.
process SEGMENTATION_FLAMES {
    tag "$meta.id"
    container 'frheault/sf-lesionflow-flames:1.0.0'

    input:
    tuple val(meta), path(flair_mni)

    output:
    tuple val(meta), path("${meta.id}_flames_binary.nii.gz"), emit: binary_mask
    tuple val(meta), path("${meta.id}_flames_prob.nii.gz")  , emit: probability_map
    path "versions.yml"                                     , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    export OMP_NUM_THREADS=${task.cpus}
    export MKL_NUM_THREADS=${task.cpus}
    export OPENBLAS_NUM_THREADS=${task.cpus}
    export PYTHONNOUSERSITE=1
    unset PYTHONPATH
    export nnUNet_results=/opt/nnunet_results
    export nnUNet_raw=/opt/nnunet_raw
    export nnUNet_preprocessed=/opt/nnunet_preprocessed
    export TORCH_HOME="\$(pwd)/.cache/torch"
    export MPLCONFIGDIR="\$(pwd)/.cache/matplotlib"

    mkdir -p in_dir out_dir
    ln -s \$(realpath ${flair_mni}) in_dir/${meta.id}_0000.nii.gz

    nnUNetv2_predict -i in_dir -o out_dir -d 004 -c 3d_fullres -tr nnUNetTrainer_8000epochs -device cpu -npp 1 -nps 1 --save_probabilities

    if [ -f "out_dir/${meta.id}.nii.gz" ]; then
        mv out_dir/${meta.id}.nii.gz ${meta.id}_flames_binary.nii.gz
    else
        echo "Error: FLAMeS output missing" >&2
        exit 1
    fi

    nnunet_probs_to_nifti.py --npz out_dir/${meta.id}.npz \
                             --ref in_dir/${meta.id}_0000.nii.gz \
                             --output ${meta.id}_flames_prob.nii.gz \
                             --check_mask ${meta.id}_flames_binary.nii.gz
    rm -rf in_dir out_dir

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        nnunet: 2.0
        flames: 1.0
    END_VERSIONS
    """

    stub:
    """
    touch ${meta.id}_flames_binary.nii.gz
    touch ${meta.id}_flames_prob.nii.gz
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        nnunet: 2.0
        flames: 1.0
    END_VERSIONS
    """
}
