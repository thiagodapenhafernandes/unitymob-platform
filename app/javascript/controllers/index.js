import { application } from "controllers/application"
import { lazyLoadControllersFrom } from "@hotwired/stimulus-loading"
import FancyboxGalleryController from "controllers/fancybox_gallery_controller"
import PublicGalleryMobileController from "controllers/public_gallery_mobile_controller"

application.register("fancybox-gallery", FancyboxGalleryController)
application.register("public-gallery-mobile", PublicGalleryMobileController)

// Composer WhatsApp: registro explicito (com catch) — nao dependemos do
// lazy-load por MutationObserver, que se mostrou fragil no PWA iOS.
;[
  ["attach-menu", "controllers/attach_menu_controller"],
  ["quick-replies", "controllers/quick_replies_controller"],
  ["emoji-picker", "controllers/emoji_picker_controller"]
].forEach(([name, path]) => {
  import(path)
    .then((module) => application.register(name, module.default))
    .catch((error) => console.error(`[stimulus] falha ao carregar ${name}:`, error))
})
lazyLoadControllersFrom("controllers", application)
