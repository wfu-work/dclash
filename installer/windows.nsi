Unicode true

!include "MUI2.nsh"
!include "x64.nsh"

!ifndef APP_NAME
  !define APP_NAME "dclash"
!endif
!ifndef APP_EXE
  !define APP_EXE "dclash.exe"
!endif
!ifndef APP_VERSION
  !define APP_VERSION "0.1.0.0"
!endif
!ifndef DISPLAY_VERSION
  !define DISPLAY_VERSION "0.1.0"
!endif
!ifndef BUILD_DIR
  !error "BUILD_DIR must point to the Flutter Windows release directory"
!endif
!ifndef OUTFILE
  !error "OUTFILE must point to the installer output path"
!endif
!ifndef INSTALLER_ICON
  !define INSTALLER_ICON "windows/runner/resources/app_icon.ico"
!endif

Name "${APP_NAME}"
Caption "${APP_NAME} ${DISPLAY_VERSION}"
OutFile "${OUTFILE}"
InstallDir "$PROGRAMFILES64\${APP_NAME}"
InstallDirRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "InstallLocation"
RequestExecutionLevel admin
BrandingText "${APP_NAME}"
Icon "${INSTALLER_ICON}"
UninstallIcon "${INSTALLER_ICON}"
SetCompressor /SOLID lzma
SetDatablockOptimize on

VIProductVersion "${APP_VERSION}"
VIFileVersion "${APP_VERSION}"
VIAddVersionKey "ProductName" "${APP_NAME}"
VIAddVersionKey "ProductVersion" "${DISPLAY_VERSION}"
VIAddVersionKey "FileDescription" "${APP_NAME} Windows desktop client"
VIAddVersionKey "FileVersion" "${DISPLAY_VERSION}"
VIAddVersionKey "CompanyName" "Cloudrift"
VIAddVersionKey "LegalCopyright" "Copyright (C) Cloudrift"

!define MUI_ABORTWARNING
!define MUI_ICON "${INSTALLER_ICON}"
!define MUI_UNICON "${INSTALLER_ICON}"
!define MUI_FINISHPAGE_RUN "$INSTDIR\${APP_EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "启动 ${APP_NAME}"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "SimpChinese"
!insertmacro MUI_LANGUAGE "English"

Section "${APP_NAME}" SecApplication
  SectionIn RO
  SetOutPath "$INSTDIR"
  File /r "${BUILD_DIR}\*"

  CreateDirectory "$SMPROGRAMS\${APP_NAME}"
  CreateShortcut "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}"
  CreateShortcut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}"

  WriteUninstaller "$INSTDIR\Uninstall.exe"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "DisplayName" "${APP_NAME}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "DisplayVersion" "${DISPLAY_VERSION}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "Publisher" "Cloudrift"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "DisplayIcon" "$INSTDIR\${APP_EXE}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "NoModify" 1
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "NoRepair" 1
SectionEnd

Section "Uninstall"
  Delete "$DESKTOP\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk"
  RMDir "$SMPROGRAMS\${APP_NAME}"
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}"
  RMDir /r "$INSTDIR"
SectionEnd
