// Phase 2 Subworkflow: Independent Algorithm Execution (Parallelised)
//
// All 14 segmentation algorithms run independently, each in its own container.
// Native-space outputs that need warping are transformed to MNI inside this
// subworkflow, so every emit is in MNI space (stripped T1+FLAIR grid).
// LESION_FINALIZE (dtype, brainmask, BIDS naming) is applied here too.
//
// Caller is responsible for passing active_algorithms (parse-time constant)
// so that groupSorted can use size: active_algorithms.size().

include { SEGMENTATION_LST_AI       } from '../../modules/local/segmentation/lst_ai/main'
include { SEGMENTATION_SAMSEG       } from '../../modules/local/segmentation/samseg/main'
include { SEGMENTATION_WMH_SYNTHSEG } from '../../modules/local/segmentation/wmh_synthseg/main'
include { SEGMENTATION_FAST_OUTLIER } from '../../modules/local/segmentation/fast_outlier/main'
include { SEGMENTATION_FLAMES       } from '../../modules/local/segmentation/flames/main'
include { SEGMENTATION_TRUENET      } from '../../modules/local/segmentation/truenet/main'
include { SEGMENTATION_HYPERMAPP3R  } from '../../modules/local/segmentation/hypermapp3r/main'
include { PREPROC_SYNTHSEG          } from '../../modules/local/preproc/synthseg/main'
include { SEGMENTATION_SEGCSVD      } from '../../modules/local/segmentation/segcsvd/main'
include { SEGMENTATION_EMORY_ROBUST } from '../../modules/local/segmentation/emory_robust/main'
include { SEGMENTATION_MARS_WMH     } from '../../modules/local/segmentation/mars_wmh/main'
include { SEGMENTATION_BAWIL        } from '../../modules/local/segmentation/bawil/main'
include { SEGMENTATION_MIMOSA       } from '../../modules/local/segmentation/mimosa/main'
include { SEGMENTATION_SHIVAI       } from '../../modules/local/segmentation/shivai/main'
include { SEGMENTATION_MINDGLIDE    } from '../../modules/local/segmentation/mindglide/main'
include { LESION_FINALIZE           } from '../../modules/local/lesion_finalize'

include { REGISTRATION_ANTSAPPLYTRANSFORMS as TRANSFORM_LST_AI_MASK_TO_MNI }     from '../../modules/nf-neuro/registration/antsapplytransforms/main'
include { REGISTRATION_ANTSAPPLYTRANSFORMS as TRANSFORM_LST_AI_PROB_TO_MNI }     from '../../modules/nf-neuro/registration/antsapplytransforms/main'
include { REGISTRATION_ANTSAPPLYTRANSFORMS as TRANSFORM_TRUENET_MASK_TO_MNI }    from '../../modules/nf-neuro/registration/antsapplytransforms/main'
include { REGISTRATION_ANTSAPPLYTRANSFORMS as TRANSFORM_TRUENET_PROB_TO_MNI }    from '../../modules/nf-neuro/registration/antsapplytransforms/main'
include { REGISTRATION_ANTSAPPLYTRANSFORMS as TRANSFORM_MARS_WMH_MASK_TO_MNI }   from '../../modules/nf-neuro/registration/antsapplytransforms/main'
include { REGISTRATION_ANTSAPPLYTRANSFORMS as TRANSFORM_MARS_WMH_PROB_TO_MNI }   from '../../modules/nf-neuro/registration/antsapplytransforms/main'
include { REGISTRATION_ANTSAPPLYTRANSFORMS as TRANSFORM_BAWIL_MASK_TO_MNI }      from '../../modules/nf-neuro/registration/antsapplytransforms/main'
include { REGISTRATION_ANTSAPPLYTRANSFORMS as TRANSFORM_BAWIL_PROB_TO_MNI }      from '../../modules/nf-neuro/registration/antsapplytransforms/main'
include { REGISTRATION_ANTSAPPLYTRANSFORMS as TRANSFORM_MINDGLIDE_MASK_TO_MNI }  from '../../modules/nf-neuro/registration/antsapplytransforms/main'
include { REGISTRATION_ANTSAPPLYTRANSFORMS as TRANSFORM_MINDGLIDE_PROB_TO_MNI }  from '../../modules/nf-neuro/registration/antsapplytransforms/main'

workflow SEGMENTATION {
    take:
    ch_mni_paired             // [meta, t1_mni, flair_mni]       — stripped MNI
    ch_mni_flair_only         // [meta, flair_mni]                — stripped MNI
    ch_mni_unstripped         // [meta, t1_unstripped_mni, flair_unstripped_mni]
    ch_flair_unstripped_mni   // [meta, flair_unstripped_mni]
    ch_t1_native_stripped     // [meta, t1_native]                — for TrueNet
    ch_flair_native_coreg     // [meta, flair_in_t1_space]        — for TrueNet
    ch_t1_pre_n4              // [meta, t1_pre_n4]                — for LST-AI
    ch_flair_pre_n4           // [meta, flair_pre_n4]             — for LST-AI
    ch_t1_native_unstripped   // [meta, t1_n4]                    — for MARS-WMH
    ch_flair_native_unstripped // [meta, flair_n4]                — for MARS-WMH
    ch_flair_native_full_fov  // [meta, flair_fullFOV]            — for BAWIL
    ch_flair_synthstrip_mask  // [meta, brainmask]                — for BAWIL
    ch_flair_native_uncrop    // [meta, flair_unstripped_crop]    — for mindGlide
    ch_session_transforms     // [meta, t1_transforms, flair_transforms]
    ch_mni_template           // single-value
    ch_fs_license             // single-value
    ch_brainmask_mni          // [meta, brainmask_mni]

    main:

    def toSingleMask = { meta, imgs -> [meta, imgs instanceof List ? imgs[0] : imgs] }

    def withTransforms = { ch, which ->
        ch.join(ch_session_transforms.map { meta, t1_tx, fl_tx -> [meta, which == 't1' ? t1_tx : fl_tx] })
          .combine(ch_mni_template)
          .map { meta, img, txs, mni -> [meta, img, mni, txs] }
    }

    // --- LST-AI (pre-N4 native-stripped → warp to MNI) ---
    ch_lst_ai_in = ch_t1_pre_n4.join(ch_flair_pre_n4)
    SEGMENTATION_LST_AI(ch_lst_ai_in)

    TRANSFORM_LST_AI_MASK_TO_MNI(
        SEGMENTATION_LST_AI.out.binary_mask
            .join(ch_session_transforms.map { meta, t1_tx, fl_tx -> [meta, fl_tx] })
            .combine(ch_mni_template)
            .map { meta, mask, txs, mni -> [meta, mask, mni, txs] }
    )
    ch_lst_ai_mni_mask = TRANSFORM_LST_AI_MASK_TO_MNI.out.warped_image.map(toSingleMask)
    TRANSFORM_LST_AI_PROB_TO_MNI(withTransforms.call(SEGMENTATION_LST_AI.out.probability_map, 'flair'))
    ch_lst_ai_mni_prob = TRANSFORM_LST_AI_PROB_TO_MNI.out.warped_image.map(toSingleMask)

    // --- SAMSEG (unstripped MNI + FS license) ---
    SEGMENTATION_SAMSEG(ch_mni_unstripped.combine(ch_fs_license))

    // --- WMH-SynthSeg (unstripped FLAIR MNI) ---
    SEGMENTATION_WMH_SYNTHSEG(ch_flair_unstripped_mni)

    // --- FAST-Outlier / FLAMeS / HyperMapp3r / MIMOSA / SHIVA-WMH (stripped MNI) ---
    SEGMENTATION_FAST_OUTLIER(ch_mni_paired)
    SEGMENTATION_FLAMES(ch_mni_flair_only)
    SEGMENTATION_HYPERMAPP3R(ch_mni_paired)
    SEGMENTATION_MIMOSA(ch_mni_paired)
    // SHIVA-WMH: add empty SWI channel (not available in this pipeline)
    SEGMENTATION_SHIVAI(ch_mni_paired.map { meta, t1, flair -> [meta, t1, flair, []] })

    // --- TrueNet (native co-registered stripped T1+FLAIR → warp to MNI) ---
    ch_native_truenet_in = ch_t1_native_stripped.join(ch_flair_native_coreg)
    SEGMENTATION_TRUENET(ch_native_truenet_in)

    TRANSFORM_TRUENET_MASK_TO_MNI(
        SEGMENTATION_TRUENET.out.binary_mask
            .join(ch_session_transforms.map { meta, t1_tx, fl_tx -> [meta, t1_tx] })
            .combine(ch_mni_template)
            .map { meta, mask, txs, mni -> [meta, mask, mni, txs] }
    )
    ch_truenet_mni_mask = TRANSFORM_TRUENET_MASK_TO_MNI.out.warped_image.map(toSingleMask)
    TRANSFORM_TRUENET_PROB_TO_MNI(withTransforms.call(SEGMENTATION_TRUENET.out.probability_map, 't1'))
    ch_truenet_mni_prob = TRANSFORM_TRUENET_PROB_TO_MNI.out.warped_image.map(toSingleMask)

    // --- SegCSVD (MNI stripped FLAIR + SynthSeg parcellation) ---
    PREPROC_SYNTHSEG(ch_mni_flair_only)
    SEGMENTATION_SEGCSVD(ch_mni_flair_only.join(PREPROC_SYNTHSEG.out.synthseg))

    // --- Emory-Robust (stripped MNI) ---
    SEGMENTATION_EMORY_ROBUST(ch_mni_paired)

    // --- MARS-WMH (native unstripped → warp to MNI) ---
    SEGMENTATION_MARS_WMH(ch_t1_native_unstripped.join(ch_flair_native_unstripped))

    TRANSFORM_MARS_WMH_MASK_TO_MNI(
        SEGMENTATION_MARS_WMH.out.binary_mask
            .join(ch_session_transforms.map { meta, t1_tx, fl_tx -> [meta, fl_tx] })
            .combine(ch_mni_template)
            .map { meta, mask, txs, mni -> [meta, mask, mni, txs] }
    )
    ch_mars_wmh_mni_mask = TRANSFORM_MARS_WMH_MASK_TO_MNI.out.warped_image.map(toSingleMask)
    TRANSFORM_MARS_WMH_PROB_TO_MNI(withTransforms.call(SEGMENTATION_MARS_WMH.out.probability_map, 'flair'))
    ch_mars_wmh_mni_prob = TRANSFORM_MARS_WMH_PROB_TO_MNI.out.warped_image.map(toSingleMask)

    // --- BAWIL (full-FOV native unstripped FLAIR + SynthStrip mask → warp to MNI) ---
    SEGMENTATION_BAWIL(ch_flair_native_full_fov.join(ch_flair_synthstrip_mask))

    TRANSFORM_BAWIL_MASK_TO_MNI(
        SEGMENTATION_BAWIL.out.binary_mask
            .join(ch_session_transforms.map { meta, t1_tx, fl_tx -> [meta, fl_tx] })
            .combine(ch_mni_template)
            .map { meta, mask, txs, mni -> [meta, mask, mni, txs] }
    )
    ch_bawil_mni_mask = TRANSFORM_BAWIL_MASK_TO_MNI.out.warped_image.map(toSingleMask)
    TRANSFORM_BAWIL_PROB_TO_MNI(withTransforms.call(SEGMENTATION_BAWIL.out.probability_map, 'flair'))
    ch_bawil_mni_prob = TRANSFORM_BAWIL_PROB_TO_MNI.out.warped_image.map(toSingleMask)

    // --- mindGlide (native unstripped cropped FLAIR → warp to MNI) ---
    SEGMENTATION_MINDGLIDE(ch_flair_native_uncrop)

    TRANSFORM_MINDGLIDE_MASK_TO_MNI(
        SEGMENTATION_MINDGLIDE.out.binary_mask
            .join(ch_session_transforms.map { meta, t1_tx, fl_tx -> [meta, fl_tx] })
            .combine(ch_mni_template)
            .map { meta, mask, txs, mni -> [meta, mask, mni, txs] }
    )
    ch_mindglide_mni_mask = TRANSFORM_MINDGLIDE_MASK_TO_MNI.out.warped_image.map(toSingleMask)
    TRANSFORM_MINDGLIDE_PROB_TO_MNI(withTransforms.call(SEGMENTATION_MINDGLIDE.out.probability_map, 'flair'))
    ch_mindglide_mni_prob = TRANSFORM_MINDGLIDE_PROB_TO_MNI.out.warped_image.map(toSingleMask)

    // --- Merge all algorithm outputs into one channel, then run LESION_FINALIZE ---
    def tagged = { String algo, ch_bin, ch_prob ->
        ch_bin.join(ch_prob, remainder: true)
              .filter { it[1] != null }
              .map { meta, bin, prob -> [meta, algo, bin, prob ?: []] }
    }

    ch_lesions_mni = tagged.call('lst_ai',       ch_lst_ai_mni_mask,                    ch_lst_ai_mni_prob)
        .mix(tagged.call('samseg',       SEGMENTATION_SAMSEG.out.binary_mask,       SEGMENTATION_SAMSEG.out.probability_map))
        .mix(tagged.call('wmh_synthseg', SEGMENTATION_WMH_SYNTHSEG.out.binary_mask, SEGMENTATION_WMH_SYNTHSEG.out.probability_map))
        .mix(tagged.call('fast_outlier', SEGMENTATION_FAST_OUTLIER.out.binary_mask, SEGMENTATION_FAST_OUTLIER.out.probability_map))
        .mix(tagged.call('flames',       SEGMENTATION_FLAMES.out.binary_mask,       SEGMENTATION_FLAMES.out.probability_map))
        .mix(tagged.call('truenet',      ch_truenet_mni_mask,                       ch_truenet_mni_prob))
        .mix(tagged.call('hypermapp3r',  SEGMENTATION_HYPERMAPP3R.out.binary_mask,  SEGMENTATION_HYPERMAPP3R.out.probability_map))
        .mix(tagged.call('segcsvd',      SEGMENTATION_SEGCSVD.out.binary_mask,      SEGMENTATION_SEGCSVD.out.probability_map))
        .mix(tagged.call('emory_robust', SEGMENTATION_EMORY_ROBUST.out.binary_mask, SEGMENTATION_EMORY_ROBUST.out.probability_map))
        .mix(tagged.call('mars_wmh',     ch_mars_wmh_mni_mask,                      ch_mars_wmh_mni_prob))
        .mix(tagged.call('bawil',        ch_bawil_mni_mask,                         ch_bawil_mni_prob))
        .mix(tagged.call('mimosa',       SEGMENTATION_MIMOSA.out.binary_mask,       SEGMENTATION_MIMOSA.out.probability_map))
        .mix(tagged.call('shivai',       SEGMENTATION_SHIVAI.out.binary_mask,       SEGMENTATION_SHIVAI.out.probability_map))
        .mix(tagged.call('mindglide',    ch_mindglide_mni_mask,                     ch_mindglide_mni_prob))

    // Grid check, brain masking, BIDS naming & JSON sidecar
    ch_finalize_in = ch_lesions_mni
        .combine(ch_brainmask_mni, by: 0)
        .combine(ch_mni_template)
    LESION_FINALIZE(ch_finalize_in)

    emit:
    // Raw per-algorithm outputs — caller (main.nf) groups with groupSorted using the
    // parse-time active_algorithms.size() constant. DSL2 take: inputs are channels;
    // groupTuple(size:) must therefore stay in main.nf where active_algorithms is a
    // plain Groovy List, not a channel value. See nextflow-io/nextflow#1702.
    lesion_finalize_masks    = LESION_FINALIZE.out.mask     // [meta, algo, mask]
    lesion_finalize_sidecars = LESION_FINALIZE.out.sidecar  // [meta, algo, sidecar]
    lesions_mni              = ch_lesions_mni
}
