process SEGMENTATION_SEGCSVD {
    tag "$meta.id"
    label 'process_gpu'
    container 'frheault/sf-lesionflow-segcsvd:rc03'

    input:
    tuple val(meta), path(flair_mni), path(synthseg)

    output:
    tuple val(meta), path("${meta.id}_segcsvd_binary.nii.gz"), emit: binary_mask
    tuple val(meta), path("${meta.id}_segcsvd_prob.nii.gz")  , emit: probability_map
    path "versions.yml"                                      , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def use_gpu    = task.ext.gpu
    def threshold  = task.ext.threshold ?: 0.35
    def patch_size = task.ext.patch_size ?: "96,128"
    """
    export OMP_NUM_THREADS=${task.cpus}
    export TORCH_HOME="\$(pwd)/.cache/torch"
    export MPLCONFIGDIR="\$(pwd)/.cache/matplotlib"

    mkdir -p "\$PWD/outdir"
    out_prob="\$PWD/outdir/prob.nii.gz"

    if [ "${use_gpu}" = "true" ]; then
        sed 's/ -c//' /seg/tools/segment_wmh > ./segment_wmh_device
        chmod +x ./segment_wmh_device
        ./segment_wmh_device ${flair_mni} ${synthseg} "\$out_prob" 1 "${patch_size}" ${threshold} 1 true true
    else
        segment_wmh ${flair_mni} ${synthseg} "\$out_prob" 1 "${patch_size}" ${threshold} 1 true true
    fi

    test -s "\$PWD/outdir/thr_prob.nii.gz" || { echo "ERROR: segment_wmh did not write its binary to outdir/thr_prob.nii.gz" >&2; exit 1; }
    python3 -c "
import sys, nibabel as nib, numpy as np
p = np.asanyarray(nib.load('outdir/prob.nii.gz').dataobj)
n = np.unique(p[p > 0]).size
sys.exit(0 if n > 2 else 'ERROR: SegCSVD probability map is not soft (%d distinct non-zero values)' % n)
"

    threshold_probmap.py --input outdir/prob.nii.gz \
                         --output ${meta.id}_segcsvd_binary.nii.gz \
                         --threshold ${threshold}

    mv outdir/prob.nii.gz ${meta.id}_segcsvd_prob.nii.gz
    rm -rf outdir segment_wmh_device

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        segcsvd: rc03
    END_VERSIONS
    """

    stub:
    """
    touch ${meta.id}_segcsvd_binary.nii.gz
    touch ${meta.id}_segcsvd_prob.nii.gz
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        segcsvd: rc03
    END_VERSIONS
    """
}
