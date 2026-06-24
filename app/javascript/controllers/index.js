import { application } from "controllers/application"
import { lazyLoadControllersFrom } from "@hotwired/stimulus-loading"
import FancyboxGalleryController from "controllers/fancybox_gallery_controller"

application.register("fancybox-gallery", FancyboxGalleryController)
lazyLoadControllersFrom("controllers", application)
