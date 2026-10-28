; Bộ cài SATF cho Windows. Build: build-win.sh (cần makensis: brew install makensis)
; Cài cho người dùng hiện tại, không cần quyền admin. Hiện trong Settings → Apps / Control Panel.
Unicode true

!ifndef VERSION
  !define VERSION "1.0.0"
!endif
!ifndef OUTFILE
  !define OUTFILE "SATF-Setup.exe"
!endif
!ifndef SOURCE
  !define SOURCE "SATF.exe"
!endif

!define APP       "SATF"
!define PUBLISHER "Tran Minh Khoi"
!define EMAIL     "contact@tranminhkhoi.dev"
!define URL       "https://tranminhkhoi.dev"
!define UNINST    "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP}"
!define RUNKEY    "Software\Microsoft\Windows\CurrentVersion\Run"

Name "${APP}"
OutFile "${OUTFILE}"
InstallDir "$LOCALAPPDATA\Programs\${APP}"
RequestExecutionLevel user
SetCompressor /SOLID lzma
BrandingText "${PUBLISHER} · tranminhkhoi.dev"

VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName"     "${APP}"
VIAddVersionKey "ProductVersion"  "${VERSION}"
VIAddVersionKey "FileVersion"     "${VERSION}"
VIAddVersionKey "CompanyName"     "${PUBLISHER}"
VIAddVersionKey "LegalCopyright"  "© 2026 ${PUBLISHER}"
VIAddVersionKey "FileDescription" "${APP} Setup"

!include "MUI2.nsh"
!include "FileFunc.nsh"

!ifndef ICON
  !define ICON "AppIcon.ico"
!endif
!define MUI_ICON   "${ICON}"
!define MUI_UNICON "${ICON}"
!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TITLE "$(WelcomeTitle)"
!define MUI_WELCOMEPAGE_TEXT "$(WelcomeText)"
!define MUI_FINISHPAGE_RUN "$INSTDIR\SATF.exe"
!define MUI_FINISHPAGE_RUN_TEXT "$(RunNow)"
; Hỏi ngôn ngữ khi mở bộ cài (English mặc định)
!define MUI_LANGDLL_ALLLANGUAGES
!define MUI_LANGDLL_REGISTRY_ROOT HKCU
!define MUI_LANGDLL_REGISTRY_KEY "${UNINST}"
!define MUI_LANGDLL_REGISTRY_VALUENAME "InstallerLanguage"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "Vietnamese"

LangString WelcomeTitle ${LANG_ENGLISH}    "Install SATF ${VERSION}"
LangString WelcomeTitle ${LANG_VIETNAMESE} "Cài đặt SATF ${VERSION}"
LangString WelcomeText  ${LANG_ENGLISH}    "Drag a file, give it a little shake, and convert it in a blink.$\r$\n$\r$\nClick Install to begin."
LangString WelcomeText  ${LANG_VIETNAMESE} "Kéo file, lắc nhẹ là đổi được định dạng ngay.$\r$\n$\r$\nBấm Cài đặt để bắt đầu."
LangString RunNow       ${LANG_ENGLISH}    "Open SATF now"
LangString RunNow       ${LANG_VIETNAMESE} "Mở SATF ngay"
LangString SecAppName    ${LANG_ENGLISH}    "SATF"
LangString SecAppName    ${LANG_VIETNAMESE} "SATF"
LangString SecAppDesc    ${LANG_ENGLISH}    "The app. Images and PDF work right away."
LangString SecAppDesc    ${LANG_VIETNAMESE} "Ứng dụng chính. Ảnh và PDF dùng được ngay."
LangString SecOfficeName ${LANG_ENGLISH}    "Word, Excel & PowerPoint add-on (~350 MB)"
LangString SecOfficeName ${LANG_VIETNAMESE} "Gói Word, Excel & PowerPoint (~350 MB)"
LangString SecOfficeDesc ${LANG_ENGLISH}    "Convert documents to PDF and images. Downloaded the first time SATF opens. Skip it if you're not sure — SATF will ask when you need it."
LangString SecOfficeDesc ${LANG_VIETNAMESE} "Đổi tài liệu sang PDF và ảnh. Tải về ở lần mở SATF đầu tiên. Chưa chắc thì bỏ qua — khi cần SATF sẽ hỏi."
LangString SecMediaName  ${LANG_ENGLISH}    "Video & music add-on (~115 MB)"
LangString SecMediaName  ${LANG_VIETNAMESE} "Gói video & nhạc (~115 MB)"
LangString SecMediaDesc  ${LANG_ENGLISH}    "Convert MP4, MP3, M4A, WAV and pull audio from videos. Downloaded the first time SATF opens."
LangString SecMediaDesc  ${LANG_VIETNAMESE} "Đổi MP4, MP3, M4A, WAV và lấy tiếng từ video. Tải về ở lần mở SATF đầu tiên."
LangString Tagline      ${LANG_ENGLISH}    "Drag, shake, convert"
LangString Tagline      ${LANG_VIETNAMESE} "Kéo, lắc, đổi file"


Function un.onInit
  !insertmacro MUI_UNGETLANGUAGE
FunctionEnd

Section "$(SecAppName)" SecApp
  SectionIn RO
  ; Đóng bản đang chạy (khi cập nhật)
  nsExec::Exec 'taskkill /f /im SATF.exe'
  Sleep 500

  SetOutPath "$INSTDIR"
  File "/oname=SATF.exe" "${SOURCE}"
  File "/oname=LICENSE.txt" "${ROOT}\LICENSE"
  File "/oname=THIRD_PARTY_NOTICES.md" "${ROOT}\THIRD_PARTY_NOTICES.md"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  CreateShortcut "$SMPROGRAMS\SATF.lnk" "$INSTDIR\SATF.exe" "" "$INSTDIR\SATF.exe" 0 SW_SHOWNORMAL "" "$(Tagline)"

  ; Mục trong Settings → Apps / Control Panel → Programs
  WriteRegStr   HKCU "${UNINST}" "DisplayName"          "${APP}"
  WriteRegStr   HKCU "${UNINST}" "DisplayVersion"       "${VERSION}"
  WriteRegStr   HKCU "${UNINST}" "Publisher"            "${PUBLISHER}"
  WriteRegStr   HKCU "${UNINST}" "URLInfoAbout"         "${URL}"
  WriteRegStr   HKCU "${UNINST}" "HelpLink"             "mailto:${EMAIL}"
  WriteRegStr   HKCU "${UNINST}" "Contact"              "${EMAIL}"
  WriteRegStr   HKCU "${UNINST}" "DisplayIcon"          "$INSTDIR\SATF.exe"
  WriteRegStr   HKCU "${UNINST}" "InstallLocation"      "$INSTDIR"
  WriteRegStr   HKCU "${UNINST}" "UninstallString"      '"$INSTDIR\Uninstall.exe"'
  WriteRegStr   HKCU "${UNINST}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
  WriteRegDWORD HKCU "${UNINST}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINST}" "NoRepair" 1
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  WriteRegDWORD HKCU "${UNINST}" "EstimatedSize" $0

  ; Ngôn ngữ chọn lúc cài -> dùng luôn cho app (chỉ lần cài đầu, không ghi đè cài đặt sẵn có)
  IfFileExists "$LOCALAPPDATA\SATF\settings.json" lang_done
    CreateDirectory "$LOCALAPPDATA\SATF"
    StrCpy $0 0
    StrCmp $LANGUAGE ${LANG_VIETNAMESE} 0 lang_write
      StrCpy $0 1
    lang_write:
    FileOpen $1 "$LOCALAPPDATA\SATF\settings.json" w
    FileWrite $1 '{"Language":$0}'
    FileClose $1
  lang_done:

  ; Mở cùng Windows (tắt được trong Cài đặt của SATF)
  WriteRegStr HKCU "${RUNKEY}" "${APP}" '"$INSTDIR\SATF.exe"'
SectionEnd

; Gói tải thêm: chỉ ghi lại lựa chọn, SATF tự tải ở lần mở đầu tiên (có thanh tiến trình)
Section /o "$(SecOfficeName)" SecOffice
  CreateDirectory "$LOCALAPPDATA\SATF"
  FileOpen $1 "$LOCALAPPDATA\SATF\pending-addons" a
  FileSeek $1 0 END
  FileWrite $1 "office$\r$\n"
  FileClose $1
SectionEnd

Section /o "$(SecMediaName)" SecMedia
  CreateDirectory "$LOCALAPPDATA\SATF"
  FileOpen $1 "$LOCALAPPDATA\SATF\pending-addons" a
  FileSeek $1 0 END
  FileWrite $1 "media$\r$\n"
  FileClose $1
SectionEnd

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${SecApp}    "$(SecAppDesc)"
  !insertmacro MUI_DESCRIPTION_TEXT ${SecOffice} "$(SecOfficeDesc)"
  !insertmacro MUI_DESCRIPTION_TEXT ${SecMedia}  "$(SecMediaDesc)"
!insertmacro MUI_FUNCTION_DESCRIPTION_END

Section "Uninstall"
  nsExec::Exec 'taskkill /f /im SATF.exe'
  Sleep 800

  Delete "$INSTDIR\SATF.exe"
  Delete "$INSTDIR\Uninstall.exe"
  Delete "$INSTDIR\LICENSE.txt"
  Delete "$INSTDIR\THIRD_PARTY_NOTICES.md"
  RMDir  "$INSTDIR"
  Delete "$SMPROGRAMS\SATF.lnk"

  ; Dọn sạch: cài đặt, gói tải thêm, nhật ký, file tạm
  RMDir /r "$LOCALAPPDATA\SATF"
  RMDir /r "$TEMP\satf-lo-profile"
  RMDir /r "$TEMP\.net\SATF"

  DeleteRegKey   HKCU "${UNINST}"
  DeleteRegValue HKCU "${RUNKEY}" "${APP}"
SectionEnd

Function .onInit
  !insertmacro MUI_LANGDLL_DISPLAY
  ; Máy đã có Word, Excel và PowerPoint -> không cần gói Office, ẩn lựa chọn này
  ReadRegStr $0 HKCR "Word.Application\CLSID" ""
  StrCmp $0 "" office_done
  ReadRegStr $0 HKCR "Excel.Application\CLSID" ""
  StrCmp $0 "" office_done
  ReadRegStr $0 HKCR "PowerPoint.Application\CLSID" ""
  StrCmp $0 "" office_done
    SectionSetText ${SecOffice} ""
  office_done:
FunctionEnd
