@echo off
setlocal EnableExtensions
pushd "%~dp0.."

if not exist sim\rtl mkdir sim\rtl
if not exist sim\cmodel mkdir sim\cmodel
if not exist sim\logs mkdir sim\logs

echo RUN_STAGE MEM_GROUP_PREREQUISITE
call scripts\run_mem_group_regression.bat ^
  > sim\logs\mem_hemisphere_group_prerequisite.log 2>&1
if errorlevel 1 goto prerequisite_fail
type sim\logs\mem_hemisphere_group_prerequisite.log
findstr /X /C:"MEM_GROUP_REGRESSION TEST_PASS" ^
  sim\logs\mem_hemisphere_group_prerequisite.log >nul
if errorlevel 1 goto prerequisite_fail

echo RUN_STAGE RTL_MEM_HEMISPHERE
iverilog -g2012 -Wall -s tb_mem_hemisphere ^
  -o sim\rtl\tb_mem_hemisphere.vvp ^
  rtl\core\mem_bank_superlane_leaf.v ^
  rtl\core\mem_bank_control_column.v ^
  rtl\core\mem_logical_bank_column.v ^
  rtl\core\mem_slice.v ^
  rtl\core\mem_group.v ^
  rtl\core\mem_hemisphere.v ^
  tb\tb_mem_hemisphere.v ^
  > sim\logs\mem_hemisphere_compile.log 2>&1
if errorlevel 1 goto rtl_compile_fail
findstr /I /C:"warning:" sim\logs\mem_hemisphere_compile.log >nul
if not errorlevel 1 goto rtl_warning_fail

vvp sim\rtl\tb_mem_hemisphere.vvp ^
  > sim\logs\mem_hemisphere_regression.log 2>&1
if errorlevel 1 goto rtl_run_fail
type sim\logs\mem_hemisphere_regression.log
findstr /C:"TEST_FAIL" sim\logs\mem_hemisphere_regression.log >nul
if not errorlevel 1 goto rtl_run_fail
findstr /X /C:"TEST_PASS" sim\logs\mem_hemisphere_regression.log >nul
if errorlevel 1 goto rtl_run_fail
echo RTL_MEM_HEMISPHERE_REGRESSION PASS

echo RUN_STAGE CMODEL_MEM_HEMISPHERE
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" goto cmodel_tool_fail
set "VSROOT="
for /f "usebackq delims=" %%I in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSROOT=%%I"
if not defined VSROOT goto cmodel_tool_fail
call "%VSROOT%\Common7\Tools\VsDevCmd.bat" -no_logo -arch=x64 -host_arch=x64 ^
  > sim\logs\mem_hemisphere_msvc_environment.log 2>&1
if errorlevel 1 goto cmodel_tool_fail

cl /nologo /std:c++17 /W4 /WX /EHsc /c cmodel\mem_model.cpp ^
  /Fo:sim\cmodel\mem_model_hemisphere.obj ^
  > sim\logs\mem_hemisphere_cmodel_compile.log 2>&1
if errorlevel 1 goto cmodel_compile_fail
cl /nologo /std:c++17 /W4 /WX /EHsc /c cmodel\mem_logical_bank_model.cpp ^
  /Fo:sim\cmodel\mem_logical_bank_model_hemisphere.obj ^
  >> sim\logs\mem_hemisphere_cmodel_compile.log 2>&1
if errorlevel 1 goto cmodel_compile_fail
cl /nologo /std:c++17 /W4 /WX /EHsc /c cmodel\mem_slice_model.cpp ^
  /Fo:sim\cmodel\mem_slice_model_hemisphere.obj ^
  >> sim\logs\mem_hemisphere_cmodel_compile.log 2>&1
if errorlevel 1 goto cmodel_compile_fail
cl /nologo /std:c++17 /W4 /WX /EHsc /c cmodel\mem_group_model.cpp ^
  /Fo:sim\cmodel\mem_group_model_hemisphere.obj ^
  >> sim\logs\mem_hemisphere_cmodel_compile.log 2>&1
if errorlevel 1 goto cmodel_compile_fail
cl /nologo /std:c++17 /W4 /WX /EHsc /c cmodel\mem_hemisphere_model.cpp ^
  /Fo:sim\cmodel\mem_hemisphere_model.obj ^
  >> sim\logs\mem_hemisphere_cmodel_compile.log 2>&1
if errorlevel 1 goto cmodel_compile_fail
cl /nologo /std:c++17 /W4 /WX /EHsc /c cmodel\test_mem_hemisphere_model.cpp ^
  /Fo:sim\cmodel\test_mem_hemisphere_model.obj ^
  >> sim\logs\mem_hemisphere_cmodel_compile.log 2>&1
if errorlevel 1 goto cmodel_compile_fail
link /NOLOGO /OUT:sim\cmodel\test_mem_hemisphere_model.exe ^
  sim\cmodel\mem_model_hemisphere.obj ^
  sim\cmodel\mem_logical_bank_model_hemisphere.obj ^
  sim\cmodel\mem_slice_model_hemisphere.obj ^
  sim\cmodel\mem_group_model_hemisphere.obj ^
  sim\cmodel\mem_hemisphere_model.obj ^
  sim\cmodel\test_mem_hemisphere_model.obj ^
  >> sim\logs\mem_hemisphere_cmodel_compile.log 2>&1
if errorlevel 1 goto cmodel_compile_fail

sim\cmodel\test_mem_hemisphere_model.exe ^
  > sim\logs\mem_hemisphere_cmodel_regression.log 2>&1
if errorlevel 1 goto cmodel_run_fail
type sim\logs\mem_hemisphere_cmodel_regression.log
findstr /C:"CMODEL_MEM_HEMISPHERE TEST_FAIL" ^
  sim\logs\mem_hemisphere_cmodel_regression.log >nul
if not errorlevel 1 goto cmodel_run_fail
findstr /X /C:"CMODEL_MEM_HEMISPHERE TEST_PASS" ^
  sim\logs\mem_hemisphere_cmodel_regression.log >nul
if errorlevel 1 goto cmodel_run_fail
echo CMODEL_MEM_HEMISPHERE_REGRESSION PASS

echo MEM_HEMISPHERE_REGRESSION TEST_PASS
popd
exit /b 0

:prerequisite_fail
type sim\logs\mem_hemisphere_group_prerequisite.log
echo MEM_GROUP_PREREQUISITE FAIL
goto fail

:rtl_compile_fail
type sim\logs\mem_hemisphere_compile.log
echo RTL_MEM_HEMISPHERE_COMPILE FAIL
goto fail

:rtl_warning_fail
type sim\logs\mem_hemisphere_compile.log
echo RTL_MEM_HEMISPHERE_WARNING_CHECK FAIL
goto fail

:rtl_run_fail
type sim\logs\mem_hemisphere_regression.log
echo RTL_MEM_HEMISPHERE_REGRESSION FAIL
goto fail

:cmodel_tool_fail
echo ERROR MSVC C++17 build tools were not found.
echo CMODEL_MEM_HEMISPHERE_REGRESSION FAIL
goto fail

:cmodel_compile_fail
type sim\logs\mem_hemisphere_cmodel_compile.log
echo CMODEL_MEM_HEMISPHERE_COMPILE FAIL
goto fail

:cmodel_run_fail
type sim\logs\mem_hemisphere_cmodel_regression.log
echo CMODEL_MEM_HEMISPHERE_REGRESSION FAIL
goto fail

:fail
echo MEM_HEMISPHERE_REGRESSION TEST_FAIL
popd
exit /b 1
