@echo off
setlocal EnableExtensions
pushd "%~dp0.."

if not exist sim\rtl mkdir sim\rtl
if not exist sim\cmodel mkdir sim\cmodel
if not exist sim\logs mkdir sim\logs

echo RUN_STAGE RTL_BANK_CONTROL
iverilog -g2012 -Wall -s tb_mem_bank_control_column ^
  -o sim\rtl\tb_mem_bank_control_column.vvp ^
  rtl\core\mem_bank_control_column.v ^
  tb\tb_mem_bank_control_column.v ^
  > sim\logs\bank_control_compile.log 2>&1
if errorlevel 1 goto control_compile_fail

vvp sim\rtl\tb_mem_bank_control_column.vvp ^
  > sim\logs\bank_control_regression.log 2>&1
if errorlevel 1 goto control_run_fail
type sim\logs\bank_control_regression.log
findstr /C:"TEST_FAIL" sim\logs\bank_control_regression.log >nul
if not errorlevel 1 goto control_run_fail
findstr /X /C:"TEST_PASS" sim\logs\bank_control_regression.log >nul
if errorlevel 1 goto control_run_fail
echo RTL_BANK_CONTROL PASS

echo RUN_STAGE RTL_LOGICAL_BANK
iverilog -g2012 -Wall -s tb_mem_logical_bank ^
  -o sim\rtl\tb_mem_logical_bank.vvp ^
  rtl\core\mem_bank_superlane_leaf.v ^
  rtl\core\mem_bank_control_column.v ^
  rtl\core\mem_logical_bank_column.v ^
  tb\tb_mem_logical_bank.v ^
  > sim\logs\logical_bank_compile.log 2>&1
if errorlevel 1 goto bank_compile_fail

vvp sim\rtl\tb_mem_logical_bank.vvp ^
  > sim\logs\logical_bank_regression.log 2>&1
if errorlevel 1 goto bank_run_fail
type sim\logs\logical_bank_regression.log
findstr /C:"TEST_FAIL" sim\logs\logical_bank_regression.log >nul
if not errorlevel 1 goto bank_run_fail
findstr /X /C:"TEST_PASS" sim\logs\logical_bank_regression.log >nul
if errorlevel 1 goto bank_run_fail
echo RTL_LOGICAL_BANK PASS
echo RTL_LOGICAL_BANK_REGRESSION PASS

echo RUN_STAGE CMODEL_LOGICAL_BANK
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" goto cmodel_tool_fail
set "VSROOT="
for /f "usebackq delims=" %%I in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSROOT=%%I"
if not defined VSROOT goto cmodel_tool_fail

call "%VSROOT%\Common7\Tools\VsDevCmd.bat" -no_logo -arch=x64 -host_arch=x64 ^
  > sim\logs\logical_bank_msvc_environment.log 2>&1
if errorlevel 1 goto cmodel_tool_fail

cl /nologo /std:c++17 /W4 /WX /EHsc /c cmodel\mem_model.cpp ^
  /Fo:sim\cmodel\mem_model_logical_bank.obj ^
  > sim\logs\logical_bank_cmodel_compile.log 2>&1
if errorlevel 1 goto cmodel_compile_fail
cl /nologo /std:c++17 /W4 /WX /EHsc /c cmodel\mem_logical_bank_model.cpp ^
  /Fo:sim\cmodel\mem_logical_bank_model.obj ^
  >> sim\logs\logical_bank_cmodel_compile.log 2>&1
if errorlevel 1 goto cmodel_compile_fail
cl /nologo /std:c++17 /W4 /WX /EHsc /c cmodel\test_mem_logical_bank_model.cpp ^
  /Fo:sim\cmodel\test_mem_logical_bank_model.obj ^
  >> sim\logs\logical_bank_cmodel_compile.log 2>&1
if errorlevel 1 goto cmodel_compile_fail
link /NOLOGO /OUT:sim\cmodel\test_mem_logical_bank_model.exe ^
  sim\cmodel\mem_model_logical_bank.obj ^
  sim\cmodel\mem_logical_bank_model.obj ^
  sim\cmodel\test_mem_logical_bank_model.obj ^
  >> sim\logs\logical_bank_cmodel_compile.log 2>&1
if errorlevel 1 goto cmodel_compile_fail

sim\cmodel\test_mem_logical_bank_model.exe ^
  > sim\logs\logical_bank_cmodel_regression.log 2>&1
if errorlevel 1 goto cmodel_run_fail
type sim\logs\logical_bank_cmodel_regression.log
findstr /C:"CMODEL_LOGICAL_BANK TEST_FAIL" sim\logs\logical_bank_cmodel_regression.log >nul
if not errorlevel 1 goto cmodel_run_fail
findstr /X /C:"CMODEL_LOGICAL_BANK TEST_PASS" sim\logs\logical_bank_cmodel_regression.log >nul
if errorlevel 1 goto cmodel_run_fail
echo CMODEL_LOGICAL_BANK_REGRESSION PASS

echo MEM_LOGICAL_BANK_REGRESSION TEST_PASS
popd
exit /b 0

:control_compile_fail
type sim\logs\bank_control_compile.log
echo RTL_BANK_CONTROL_COMPILE FAIL
goto fail

:control_run_fail
type sim\logs\bank_control_regression.log
echo RTL_BANK_CONTROL FAIL
goto fail

:bank_compile_fail
type sim\logs\logical_bank_compile.log
echo RTL_LOGICAL_BANK_COMPILE FAIL
goto fail

:bank_run_fail
type sim\logs\logical_bank_regression.log
echo RTL_LOGICAL_BANK FAIL
goto fail

:cmodel_tool_fail
echo ERROR MSVC C++17 build tools were not found.
echo CMODEL_LOGICAL_BANK_REGRESSION FAIL
goto fail

:cmodel_compile_fail
type sim\logs\logical_bank_cmodel_compile.log
echo CMODEL_LOGICAL_BANK_COMPILE FAIL
goto fail

:cmodel_run_fail
type sim\logs\logical_bank_cmodel_regression.log
echo CMODEL_LOGICAL_BANK_REGRESSION FAIL
goto fail

:fail
echo MEM_LOGICAL_BANK_REGRESSION TEST_FAIL
popd
exit /b 1
