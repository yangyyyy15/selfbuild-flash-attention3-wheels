$ErrorActionPreference = "Stop"

Write-Host "Building SageAttention wheel for RTX 5090D..."
Write-Host "Target: Python 3.10 | PyTorch 2.7.0 | CUDA 12.8 | Arch sm_120"

# 配置 CUDA 环境变量
$env:CUDA_HOME = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8"
$env:PATH = "$($env:CUDA_HOME)\bin;$($env:PATH)"
$env:LD_LIBRARY_PATH = "$($env:CUDA_HOME)\lib64;$($env:LD_LIBRARY_PATH)"

# 核心修改：强制指定 Blackwell 架构算力 12.0
$env:TORCH_CUDA_ARCH_LIST = "12.0"
$env:DISTUTILS_USE_SDK = 1
$env:MAX_JOBS = "4"

Write-Host "Installing dependencies..."
python -m pip install --upgrade pip
pip install ninja packaging wheel setuptools numpy

# 安装与你整合包完全一致的 PyTorch 版本
pip install torch==2.7.0 --index-url "https://download.pytorch.org/whl/cu128"

# 在临时目录克隆 SageAttention
$workDir = New-TemporaryFile | %{ Remove-Item $_; New-Item -ItemType Directory -Path $_.FullName }
Set-Location $workDir
git clone https://github.com/thu-ml/SageAttention.git
Set-Location SageAttention

# 查找 GitHub Windows Runner 中的 MSVC 编译器
$vcvarsallPath = "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvarsall.bat"
if (-not (Test-Path $vcvarsallPath)) {
    Write-Error "vcvarsall.bat not found. MSVC compiler is required."
    exit 1
}

Write-Host "Building wheel..."
# 激活 MSVC 环境并打包
$buildCmd = "`"$vcvarsallPath`" x64 && python setup.py bdist_wheel 2>&1"
cmd /c $buildCmd 

$builtWheel = Get-ChildItem -Path dist -Filter *.whl | Select-Object -First 1
if (-not $builtWheel) {
    Write-Error "Error: Wheel compilation failed."
    exit 1
}

# 移动到输出目录供 GitHub Action 上传
$outputDir = "C:\tmp\wheels"
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
Copy-Item $builtWheel.FullName -Destination $outputDir -Force
Write-Host "Wheel successfully saved to $outputDir"
