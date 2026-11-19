import { ScrollStyle } from "./scroll_style";
import { FileUploadDragNDrop } from "./file_upload_drag_n_drop";
import { FileUploadDragState } from "./file_upload_drag_state";
import { PDFViewer } from "./pdf_viewer";
import { Tippy, TippyWhenTruncated } from "./tippy";
import { AirDatepicker } from "./air_datepicker";
import { Timer } from "./timer";
import { FocusOnMount } from "./focus_on_mount";
import { ListboxKeys } from "./listbox_keys";
import Popover from "./popover";
import { ConfirmLeave } from "./confirm_leave";
import { CopyToClipboard } from "./copy_to_clipboard";
import { PaperPlane } from "./paper_plane";
import { UIHooks } from "../ui/hooks";
import { CookieConsent } from "./cookie_consent";
import { DownloadPdf } from "./download_pdf";
import { LandingNavbarTheme } from "./landing_navbar_theme";
import { LandingHero } from "./landing_hero";
import { LandingPricing } from "./landing_pricing";
import { NumberPopIn } from "./number_pop_in";
import { ImageLoadReveal } from "./image_load_reveal";
import { AssistantChat } from "./assistant";

export const Hooks = {
  ...UIHooks,
  AssistantChat,
  ScrollStyle,
  FileUploadDragNDrop,
  FileUploadDragState,
  PDFViewer,
  Tippy,
  TippyWhenTruncated,
  AirDatepicker,
  Timer,
  FocusOnMount,
  ListboxKeys,
  Popover,
  ConfirmLeave,
  CopyToClipboard,
  PaperPlane,
  CookieConsent,
  DownloadPdf,
  LandingNavbarTheme,
  LandingHero,
  LandingPricing,
  NumberPopIn,
  ImageLoadReveal
};
