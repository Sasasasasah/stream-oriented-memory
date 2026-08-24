@echo off
setlocal EnableExtensions
pushd "%~dp0.."

if not exist sim\rtl mkdir sim\rtl
if not exist sim\logs mkdir sim\logs

echo RUN_STAGE MEM_HEMISPHERE_PREREQUISITE
call scripts\run_mem_hemisphere_regression.bat ^
  > sim\logs\mem_full_hemisphere_prerequisite.log 2>&1
if errorlevel 1 goto prerequisite_fail
type sim\logs\mem_full_hemisphere_prerequisite.log
findstr /X /C:"MEM_HEMISPHERE_REGRESSION TEST_PASS" ^
  sim\logs\mem_full_hemisphere_prerequisite.log >nul
if errorlevel 1 goto prerequisite_fail

echo RUN_STAGE RTL_MEM_FULL
iverilog -g2012 -Wall -s tb_mem_full ^
  -o sim\rtl\tb_mem_full.vvp ^
  rtl\core\mem_bank_superlane_leaf.v ^
  rtl\core\mem_bank_control_column.v ^
  rtl\core\mem_logical_bank_column.v ^
  rtl\core\mem_slice.v ^
  rtl\core\mem_group.v ^
  rtl\core\mem_hemisphere.v ^
  rtl\core\mem_full.v ^
  tb\tb_mem_full.v ^
  > sim\logs\mem_full_compile.log 2>&1
if errorlevel 1 goto rtl_compile_fail
findstr /I /C:"warning:" sim\logs\mem_full_compile.log >nul
if not errorlevel 1 goto rtl_warning_fail

vvp sim\rtl\tb_mem_full.vvp > sim\logs\mem_full_regression.log 2>&1
if errorlevel 1 goto rtl_run_fail
type sim\logs\mem_full_regression.log
findstr /C:"TEST_FAIL" sim\logs\mem_full_regression.log >nul
if not errorlevel 1 goto rtl_run_fail
findstr /X /C:"TEST_PASS" sim\logs\mem_full_regression.log >nul
if errorlevel 1 goto rtl_run_fail
echo RTL_MEM_FULL_REGRESSION PASS

echo MEM_FULL_REGRESSION TEST_PASS
popd
exit /b 0

:prerequisite_fail
type sim\logs\mem_full_hemisphere_prerequisite.log
echo MEM_HEMISPHERE_PREREQUISITE FAIL
goto fail

:rtl_compile_fail
type sim\logs\mem_full_compile.log
echo RTL_MEM_FULL_COMPILE FAIL
goto fail

:rtl_warning_fail
type sim\logs\mem_full_compile.log
echo RTL_MEM_FULL_WARNING_CHECK FAIL
goto fail

:rtl_run_fail
type sim\logs\mem_full_regression.log
echo RTL_MEM_FULL_REGRESSION FAIL
goto fail

:fail
echo MEM_FULL_REGRESSION TEST_FAIL
popd
exit /b 1
