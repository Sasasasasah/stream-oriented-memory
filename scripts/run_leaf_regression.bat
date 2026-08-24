@echo off
setlocal EnableExtensions
pushd "%~dp0.."

if not exist sim\rtl mkdir sim\rtl
if not exist sim\cmodel mkdir sim\cmodel
if not exist sim\logs mkdir sim\logs

echo RUN_STAGE RTL_LEAF
iverilog -g2012 -Wall -s tb_mem_bank_superlane_leaf ^
  -o sim\rtl\tb_mem_bank_superlane_leaf.vvp ^
  rtl\core\mem_bank_superlane_leaf.v ^
  tb\tb_mem_bank_superlane_leaf.v ^
  > sim\logs\rtl_compile.log 2>&1
if errorlevel 1 goto rtl_compile_fail

vvp sim\rtl\tb_mem_bank_superlane_leaf.vvp ^
  > sim\logs\rtl_regression.log 2>&1
if errorlevel 1 goto rtl_run_fail
type sim\logs\rtl_regression.log
findstr /C:"TEST_FAIL" sim\logs\rtl_regression.log >nul
if not errorlevel 1 goto rtl_run_fail
findstr /X /C:"TEST_PASS" sim\logs\rtl_regression.log >nul
if errorlevel 1 goto rtl_run_fail
echo RTL_LEAF_REGRESSION PASS

echo RUN_STAGE CMODEL_LEAF
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" goto cmodel_tool_fail
set "VSROOT="
for /f "usebackq delims=" %%I in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSROOT=%%I"
if not defined VSROOT goto cmodel_tool_fail

call "%VSROOT%\Common7\Tools\VsDevCmd.bat" -no_logo -arch=x64 -host_arch=x64 ^
  > sim\logs\msvc_environment.log 2>&1
if errorlevel 1 goto cmodel_tool_fail

cl /nologo /std:c++17 /W4 /WX /EHsc /c cmodel\mem_model.cpp ^
  /Fo:sim\cmodel\mem_model.obj > sim\logs\cmodel_compile.log 2>&1
if errorlevel 1 goto cmodel_compile_fail
cl /nologo /std:c++17 /W4 /WX /EHsc /c cmodel\test_mem_model.cpp ^
  /Fo:sim\cmodel\test_mem_model.obj >> sim\logs\cmodel_compile.log 2>&1
if errorlevel 1 goto cmodel_compile_fail
link /NOLOGO /OUT:sim\cmodel\test_mem_model.exe ^
  sim\cmodel\mem_model.obj sim\cmodel\test_mem_model.obj ^
  >> sim\logs\cmodel_compile.log 2>&1
if errorlevel 1 goto cmodel_compile_fail

sim\cmodel\test_mem_model.exe > sim\logs\cmodel_regression.log 2>&1
if errorlevel 1 goto cmodel_run_fail
type sim\logs\cmodel_regression.log
findstr /C:"CMODEL_TEST_FAIL" sim\logs\cmodel_regression.log >nul
if not errorlevel 1 goto cmodel_run_fail
findstr /X /C:"CMODEL_TEST_PASS" sim\logs\cmodel_regression.log >nul
if errorlevel 1 goto cmodel_run_fail
echo CMODEL_LEAF_REGRESSION PASS

echo MEM_LEAF_REGRESSION TEST_PASS
popd
exit /b 0

:rtl_compile_fail
type sim\logs\rtl_compile.log
echo RTL_LEAF_COMPILE FAIL
goto fail

:rtl_run_fail
type sim\logs\rtl_regression.log
echo RTL_LEAF_REGRESSION FAIL
goto fail

:cmodel_tool_fail
echo ERROR MSVC C++17 build tools were not found.
echo CMODEL_LEAF_REGRESSION FAIL
goto fail

:cmodel_compile_fail
type sim\logs\cmodel_compile.log
echo CMODEL_LEAF_COMPILE FAIL
goto fail

:cmodel_run_fail
type sim\logs\cmodel_regression.log
echo CMODEL_LEAF_REGRESSION FAIL
goto fail

:fail
echo MEM_LEAF_REGRESSION TEST_FAIL
popd
exit /b 1
