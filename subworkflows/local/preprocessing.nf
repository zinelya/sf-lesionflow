// Phase 1 Subworkflow: Preprocessing, Coregistration & Standard-Space Projection
//
// Inputs:
//   ch_t1          [meta, t1_file]
//   ch_flair       [meta, flair_file]
//   ch_mni_template  single-value channel of MNI template path
//
// Emits:
//   t1_mni               [meta, t1_stripped_mni]
//   flair_mni            [meta, flair_stripped_mni]
//   t1_unstripped_mni    [meta, t1_unstripped_mni]
//   flair_unstripped_mni [meta, flair_unstripped_mni]
//   brainmask_mni        [meta, brainmask_mni]
//   t1_native_stripped   [meta, t1_stripped_native]   (for TrueNet)
//   flair_native_stripped [meta, flair_coregistered]  (for TrueNet - FLAIR in T1 space)
//   t1_pre_n4            [meta, t1_pre_n4]            (for LST-AI)
//   flair_pre_n4         [meta, flair_pre_n4]         (for LST-AI)
//   t1_native_unstripped [meta, t1_native_unstripped] (for MARS-WMH)
//   flair_native_unstripped [meta, flair_native_unstripped] (for MARS-WMH)
//   flair_native_full_fov   [meta, flair_native_full_fov]  (for BAWIL - full FOV)
//   flair_synthstrip_mask   [meta, flair_brain_mask]        (for BAWIL)
//   flair_native_unstripped_crop [meta, flair_unstripped_crop]  (for mindGlide)
//   session_transforms   [meta, t1_transforms, flair_transforms]

include { IMAGE_RESAMPLE as RESAMPLE_T1 }                  from '../../modules/nf-neuro/image/resample/main'
include { IMAGE_RESAMPLE as RESAMPLE_FLAIR }               from '../../modules/nf-neuro/image/resample/main'
include { BETCROP_SYNTHSTRIP as SYNTHSTRIP_T1 }            from '../../modules/nf-neuro/betcrop/synthstrip/main'
include { BETCROP_SYNTHSTRIP as SYNTHSTRIP_FLAIR }         from '../../modules/nf-neuro/betcrop/synthstrip/main'
include { PREPROC_N4 as N4_T1 }                            from '../../modules/nf-neuro/preproc/n4/main'
include { PREPROC_N4 as N4_FLAIR }                         from '../../modules/nf-neuro/preproc/n4/main'
include { IMAGE_APPLYMASK as MASK_T1 }                     from '../../modules/nf-neuro/image/applymask/main'
include { IMAGE_APPLYMASK as MASK_FLAIR }                  from '../../modules/nf-neuro/image/applymask/main'
include { IMAGE_APPLYMASK as MASK_T1_PRE_N4 }             from '../../modules/nf-neuro/image/applymask/main'
include { IMAGE_APPLYMASK as MASK_FLAIR_PRE_N4 }          from '../../modules/nf-neuro/image/applymask/main'
include { IMAGE_CROPVOLUME as CROP_T1_MASK }              from '../../modules/nf-neuro/image/cropvolume/main'
include { IMAGE_CROPVOLUME as CROP_T1_RAW }               from '../../modules/nf-neuro/image/cropvolume/main'
include { IMAGE_CROPVOLUME as CROP_FLAIR_RAW }            from '../../modules/nf-neuro/image/cropvolume/main'
include { IMAGE_CROPVOLUME as CROP_FLAIR_MASK }           from '../../modules/nf-neuro/image/cropvolume/main'

include { REGISTRATION_ANTS as REGISTER_FLAIR_TO_T1 }     from '../../modules/nf-neuro/registration/ants/main'
include { REGISTRATION_ANTS as REGISTER_T1_TO_BASELINE }  from '../../modules/nf-neuro/registration/ants/main'
include { REGISTRATION_ANTS as REGISTER_BASELINE_TO_MNI } from '../../modules/nf-neuro/registration/ants/main'

include { REGISTRATION_ANTSAPPLYTRANSFORMS as TRANSFORM_T1W_TO_MNI }              from '../../modules/nf-neuro/registration/antsapplytransforms/main'
include { REGISTRATION_ANTSAPPLYTRANSFORMS as TRANSFORM_FLAIR_TO_MNI }            from '../../modules/nf-neuro/registration/antsapplytransforms/main'
include { REGISTRATION_ANTSAPPLYTRANSFORMS as TRANSFORM_T1W_UNSTRIPPED_TO_MNI }   from '../../modules/nf-neuro/registration/antsapplytransforms/main'
include { REGISTRATION_ANTSAPPLYTRANSFORMS as TRANSFORM_FLAIR_UNSTRIPPED_TO_MNI } from '../../modules/nf-neuro/registration/antsapplytransforms/main'
include { REGISTRATION_ANTSAPPLYTRANSFORMS as TRANSFORM_T1_BRAINMASK_TO_MNI }     from '../../modules/nf-neuro/registration/antsapplytransforms/main'

workflow PREPROCESSING {
    take:
    ch_t1           // [meta, t1_file]
    ch_flair        // [meta, flair_file]
    ch_mni_template // single-value channel (MNI template path)

    main:

    // 1. Resample to isotropic 1×1×1 mm
    RESAMPLE_T1(ch_t1.map { meta, t1 -> [meta, t1, []] })
    RESAMPLE_FLAIR(ch_flair.map { meta, flair -> [meta, flair, []] })

    // 2. SynthStrip skull-strip
    SYNTHSTRIP_T1(RESAMPLE_T1.out.image.map { meta, img -> [meta, img, []] })
    SYNTHSTRIP_FLAIR(RESAMPLE_FLAIR.out.image.map { meta, img -> [meta, img, []] })

    // 3. Brain-mask-based bounding-box crop (each modality uses its own mask)
    CROP_T1_MASK(SYNTHSTRIP_T1.out.brain_mask.map { meta, mask -> [meta, mask, []] })
    CROP_T1_RAW(RESAMPLE_T1.out.image.join(CROP_T1_MASK.out.bounding_box))
    CROP_FLAIR_MASK(SYNTHSTRIP_FLAIR.out.brain_mask.map { meta, mask -> [meta, mask, []] })
    CROP_FLAIR_RAW(RESAMPLE_FLAIR.out.image.join(CROP_FLAIR_MASK.out.bounding_box))

    // 4. N4 Bias Field Correction on cropped native volumes
    ch_n4_t1_in = CROP_T1_RAW.out.image
        .join(CROP_T1_MASK.out.image)
        .map { meta, img, mask -> [meta, img, [], [], mask] }
    N4_T1(ch_n4_t1_in)

    ch_n4_flair_in = CROP_FLAIR_RAW.out.image
        .join(CROP_FLAIR_MASK.out.image)
        .map { meta, img, mask -> [meta, img, [], [], mask] }
    N4_FLAIR(ch_n4_flair_in)

    // 5. Apply brain mask to get skull-stripped images
    MASK_T1(N4_T1.out.image.join(CROP_T1_MASK.out.image))
    MASK_FLAIR(N4_FLAIR.out.image.join(CROP_FLAIR_MASK.out.image))

    // Pre-N4 skull-stripped images for algorithms that deliberately exclude N4 (LST-AI)
    MASK_T1_PRE_N4(CROP_T1_RAW.out.image.join(CROP_T1_MASK.out.image))
    MASK_FLAIR_PRE_N4(CROP_FLAIR_RAW.out.image.join(CROP_FLAIR_MASK.out.image))

    // 6. Intra-session FLAIR → T1w rigid registration
    ch_flair_to_t1 = MASK_T1.out.image
        .join(MASK_FLAIR.out.image)
        .map { meta, t1, flair -> [meta, t1, flair, [], []] }
    REGISTER_FLAIR_TO_T1(ch_flair_to_t1)

    // 7. Longitudinal: session T1w → baseline T1w
    ch_grouped_t1 = MASK_T1.out.image
        .map { meta, img -> [meta.subject, meta, img] }
        .groupTuple(by: 0)
        .flatMap { subject, metas, imgs ->
            def sorted = [metas, imgs].transpose().sort { a, b -> a[0].session <=> b[0].session }
            def baseline_meta = sorted[0][0]
            def baseline_img  = sorted[0][1]
            sorted.collect { meta, img ->
                [ meta, baseline_img, img, (meta.session == baseline_meta.session) ]
            }
        }

    ch_baseline_t1 = ch_grouped_t1.filter { meta, base_img, cur_img, is_base -> is_base }
        .map { meta, base_img, cur_img, is_base -> [meta, cur_img] }
    ch_followup_t1 = ch_grouped_t1.filter { meta, base_img, cur_img, is_base -> !is_base }
        .map { meta, base_img, cur_img, is_base -> [meta, base_img, cur_img, [], []] }

    REGISTER_T1_TO_BASELINE(ch_followup_t1)

    // 8. Baseline T1w → MNI template registration
    ch_base_to_mni = ch_baseline_t1
        .combine(ch_mni_template)
        .map { meta, t1, mni -> [meta, mni, t1, [], []] }
    REGISTER_BASELINE_TO_MNI(ch_base_to_mni)

    // 9. Compose per-session transform chains
    ch_mni_affine = REGISTER_BASELINE_TO_MNI.out.forward_affine
        .map { meta, aff -> [meta.subject, aff] }
    ch_intra_affine = REGISTER_T1_TO_BASELINE.out.forward_affine
        .map { meta, aff -> [meta.id, aff] }

    ch_session_transforms = MASK_T1.out.image
        .map { meta, img -> [meta.subject, meta] }
        .combine(ch_mni_affine, by: 0)
        .map { subject, meta, mni_aff -> [meta.id, meta, mni_aff] }
        .join(ch_intra_affine, remainder: true)
        .join(REGISTER_FLAIR_TO_T1.out.forward_affine.map { meta, aff -> [meta.id, aff] })
        .map { id, meta, mni_aff, intra_aff, flair_aff ->
            def t1_transforms    = intra_aff ? [mni_aff, intra_aff] : [mni_aff]
            def flair_transforms = intra_aff ? [mni_aff, intra_aff, flair_aff] : [mni_aff, flair_aff]
            [ meta, t1_transforms, flair_transforms ]
        }

    // 10. Warp stripped volumes to MNI
    def toMniSpace = { meta, imgs -> [meta, imgs instanceof List ? imgs.find { it.name.endsWith('space-MNI.nii.gz') } : imgs] }

    ch_warp_t1 = MASK_T1.out.image
        .join(ch_session_transforms.map { meta, t1_tx, fl_tx -> [meta, t1_tx] })
        .combine(ch_mni_template)
        .map { meta, img, txs, mni -> [meta, img, mni, txs] }
    TRANSFORM_T1W_TO_MNI(ch_warp_t1)

    ch_warp_flair = MASK_FLAIR.out.image
        .join(ch_session_transforms.map { meta, t1_tx, fl_tx -> [meta, fl_tx] })
        .combine(ch_mni_template)
        .map { meta, img, txs, mni -> [meta, img, mni, txs] }
    TRANSFORM_FLAIR_TO_MNI(ch_warp_flair)

    // 11. Warp unstripped volumes to MNI (for SAMSEG / WMH-SynthSeg)
    ch_warp_t1_unstripped = N4_T1.out.image
        .join(ch_session_transforms.map { meta, t1_tx, fl_tx -> [meta, t1_tx] })
        .combine(ch_mni_template)
        .map { meta, img, txs, mni -> [meta, img, mni, txs] }
    TRANSFORM_T1W_UNSTRIPPED_TO_MNI(ch_warp_t1_unstripped)

    ch_warp_flair_unstripped = N4_FLAIR.out.image
        .join(ch_session_transforms.map { meta, t1_tx, fl_tx -> [meta, fl_tx] })
        .combine(ch_mni_template)
        .map { meta, img, txs, mni -> [meta, img, mni, txs] }
    TRANSFORM_FLAIR_UNSTRIPPED_TO_MNI(ch_warp_flair_unstripped)

    // 12. Warp T1 brain mask to MNI (NearestNeighbor)
    ch_warp_brainmask = CROP_T1_MASK.out.image
        .join(ch_session_transforms.map { meta, t1_tx, fl_tx -> [meta, t1_tx] })
        .combine(ch_mni_template)
        .map { meta, img, txs, mni -> [meta, img, mni, txs] }
    TRANSFORM_T1_BRAINMASK_TO_MNI(ch_warp_brainmask)

    emit:
    t1_mni               = TRANSFORM_T1W_TO_MNI.out.warped_image.map { meta, imgs ->
                               [meta, imgs instanceof List ? imgs.find { it.name.endsWith('space-MNI.nii.gz') } : imgs] }
    flair_mni            = TRANSFORM_FLAIR_TO_MNI.out.warped_image.map { meta, imgs ->
                               [meta, imgs instanceof List ? imgs.find { it.name.endsWith('space-MNI.nii.gz') } : imgs] }
    t1_unstripped_mni    = TRANSFORM_T1W_UNSTRIPPED_TO_MNI.out.warped_image.map { meta, imgs ->
                               [meta, imgs instanceof List ? imgs.find { it.name.endsWith('space-MNI.nii.gz') } : imgs] }
    flair_unstripped_mni = TRANSFORM_FLAIR_UNSTRIPPED_TO_MNI.out.warped_image.map { meta, imgs ->
                               [meta, imgs instanceof List ? imgs.find { it.name.endsWith('space-MNI.nii.gz') } : imgs] }
    brainmask_mni        = TRANSFORM_T1_BRAINMASK_TO_MNI.out.warped_image.map { meta, imgs ->
                               [meta, imgs instanceof List ? imgs.find { it.name.endsWith('space-MNI.nii.gz') } : imgs] }
    t1_native_stripped   = MASK_T1.out.image
    flair_native_coregistered = REGISTER_FLAIR_TO_T1.out.image_warped
    t1_pre_n4            = MASK_T1_PRE_N4.out.image
    flair_pre_n4         = MASK_FLAIR_PRE_N4.out.image
    t1_native_unstripped = N4_T1.out.image
    flair_native_unstripped = N4_FLAIR.out.image
    flair_native_full_fov   = RESAMPLE_FLAIR.out.image
    flair_synthstrip_mask   = SYNTHSTRIP_FLAIR.out.brain_mask
    flair_native_unstripped_crop = CROP_FLAIR_RAW.out.image
    session_transforms   = ch_session_transforms
    // Registration QC outputs
    reg_flair_to_t1_affine    = REGISTER_FLAIR_TO_T1.out.forward_affine
    reg_t1_to_baseline_affine = REGISTER_T1_TO_BASELINE.out.forward_affine
    reg_t1_to_baseline_warped = REGISTER_T1_TO_BASELINE.out.image_warped
    reg_baseline_to_mni_warped = REGISTER_BASELINE_TO_MNI.out.image_warped
    reg_baseline_to_mni_affine = REGISTER_BASELINE_TO_MNI.out.forward_affine
    grouped_t1_meta       = ch_grouped_t1
    versions = RESAMPLE_T1.out.versions
        .mix(SYNTHSTRIP_T1.out.versions)
        .mix(CROP_T1_MASK.out.versions)
        .mix(N4_T1.out.versions)
        .mix(MASK_T1.out.versions)
        .mix(REGISTER_FLAIR_TO_T1.out.versions)
        .mix(REGISTER_T1_TO_BASELINE.out.versions)
        .mix(REGISTER_BASELINE_TO_MNI.out.versions)
        .mix(TRANSFORM_T1W_TO_MNI.out.versions)
}
