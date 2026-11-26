process SEGMENTATION_SAMSEG {
    tag "$meta.id"
    container 'freesurfer/freesurfer:7.4.1'

    input:
    tuple val(meta), path(t1_unstripped_mni), path(flair_unstripped_mni), path(fs_license)

    output:
    tuple val(meta), path("${meta.id}_samseg_binary.nii.gz"), emit: binary_mask
    tuple val(meta), path("${meta.id}_samseg_prob.nii.gz")  , emit: probability_map
    path "versions.yml"                                     , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    set +u
    export FREESURFER_HOME=/usr/local/freesurfer
    export FS_LICENSE=${fs_license}
    source /usr/local/freesurfer/SetUpFreeSurfer.sh
    set -u

    mkdir -p samseg_out
    run_samseg -i ${t1_unstripped_mni} -i ${flair_unstripped_mni} \
               --out samseg_out \
               --lesion \
               --lesion-mask-pattern 0 1 \
               --pallidum-separate \
               --save-posteriors Lesions \
               --threads ${task.cpus}

    if [ -f "samseg_out/seg.mgz" ]; then
        mri_binarize --i samseg_out/seg.mgz --match 99 --o ${meta.id}_samseg_binary.nii.gz
    else
        echo "Error: SAMSEG output seg.mgz missing" >&2
        exit 1
    fi
    if [ -f "samseg_out/posteriors/Lesions.mgz" ]; then
        mri_convert samseg_out/posteriors/Lesions.mgz ${meta.id}_samseg_prob.nii.gz
    else
        echo "Error: SAMSEG lesion posterior missing" >&2
        ls samseg_out/posteriors >&2 || true
        exit 1
    fi
    rm -rf samseg_out

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        samseg: 7.4.1
    END_VERSIONS
    """

    stub:
    """
    touch ${meta.id}_samseg_binary.nii.gz
    touch ${meta.id}_samseg_prob.nii.gz
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        samseg: 7.4.1
    END_VERSIONS
    """
}
