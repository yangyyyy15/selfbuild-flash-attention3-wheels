$ErrorActionPreference = "Stop"

Write-Host "Building Flash-Attention 3 wheel for RTX 5090D..."
Write-Host "Target: Python 3.10 | PyTorch 2.7.0 | CUDA 12.8 | Arch sm_120"

# 配置 CUDA 环境变量
$env:CUDA_HOME = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8"
$env:PATH = "$($env:CUDA_HOME)\bin;$($env:PATH)"
$env:LD_LIBRARY_PATH = "$($env:CUDA_HOME)\lib64;$($env:LD_LIBRARY_PATH)"

# 强制指定 Blackwell 架构算力 12.0
$env:TORCH_CUDA_ARCH_LIST = "12.0"
$env:MAX_JOBS = "4"
$env:FLASH_ATTENTION_FORCE_BUILD = "TRUE"
$env:CL = "/wd4996"
$env:NVCC_PREPEND_FLAGS = "-Xcudafe --diag_suppress=177 -Xcudafe --diag_suppress=221 -Xcudafe --diag_suppress=186 -Xcudafe --diag_suppress=550"
$env:DISTUTILS_USE_SDK = 1
$env:PYTHONUNBUFFERED = 1

Write-Host "Installing dependencies..."
python -m pip install --upgrade pip
pip install ninja packaging wheel setuptools numpy change-wheel-version
pip install torch==2.7.0 --index-url "https://download.pytorch.org/whl/cu128"

# 设置工作目录
$workDir = New-TemporaryFile | %{ Remove-Item $_; New-Item -ItemType Directory -Path $_.FullName }
$patchFile = Join-Path $PSScriptRoot "windows_fix.patch"

Set-Location $workDir
# 克隆 FA3 官方仓库
git -c core.autocrlf=false clone --recursive https://github.com/Dao-AILab/flash-attention.git
Set-Location flash-attention

Write-Host "Applying Windows build fix patch..."
git apply --ignore-whitespace $patchFile
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to apply patch"
    exit 1
}
Write-Host "Patch applied successfully"

# FA3 的代码在 hopper 目录下
Set-Location hopper

# 查找 MSVC 编译器
$vcvarsallPath = "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvarsall.bat"
if (-not (Test-Path $vcvarsallPath)) {
    Write-Error "vcvarsall.bat not found. MSVC compiler is required."
    exit 1
}

Write-Host "Building FA3 wheel..."
$buildCmd = "`"$vcvarsallPath`" x64 && python setup.py bdist_wheel 2>&1"
cmd /c $buildCmd | Select-String -Pattern 'ptxas info|bytes stack frame,' -NotMatch

$builtWheel = Get-ChildItem -Path dist -Filter *.whl | Select-Object -First 1
if (-not $builtWheel) {
    Write-Error "Error: Wheel compilation failed."
    exit 1
}

# 输出打包
$outputDir = "C:\tmp\wheels"
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
Copy-Item $builtWheel.FullName -Destination $outputDir -Force
Write-Host "Wheel successfully saved to $outputDir"
