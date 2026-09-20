param(
    [string]$ScriptPath = "TVVideoConverter.ps1",
    [string]$ExePath = "VideoConverter_VZSG.exe"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $root) { $root = Get-Location }
$fullSource = Join-Path $root $ScriptPath
$fullOutput = Join-Path $root $ExePath

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " Compilando VideoConverter VZSG a EXE" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $fullSource)) {
    throw "No se encontró el archivo: $fullSource"
}

$scriptContent = [System.IO.File]::ReadAllText($fullSource, [System.Text.Encoding]::UTF8)
$bytes = [System.Text.Encoding]::UTF8.GetBytes($scriptContent)
$base64Script = [System.Convert]::ToBase64String($bytes, [System.Base64FormattingOptions]::None)

$cSharpCode = @"
using System;
using System.IO;
using System.Text;
using System.Windows.Forms;
using System.Management.Automation;

namespace VideoConverterVZSG
{
    static class Program
    {
        [STAThread]
        static void Main(string[] args)
        {
            try
            {
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);

                string base64 = "$base64Script";
                byte[] data = Convert.FromBase64String(base64);
                string scriptText = Encoding.UTF8.GetString(data);

                using (PowerShell ps = PowerShell.Create())
                {
                    ps.AddScript(scriptText);
                    ps.Invoke();
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show("Error al ejecutar la aplicación:\n\n" + ex.Message, "VideoConverter VZSG", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
    }
}
"@

$providerOptions = New-Object 'System.Collections.Generic.Dictionary[string,string]'
$providerOptions.Add("CompilerVersion", "v4.0")
$codeProvider = New-Object Microsoft.CSharp.CSharpCodeProvider($providerOptions)

$compileParams = New-Object System.CodeDom.Compiler.CompilerParameters
$compileParams.GenerateExecutable = $true
$compileParams.OutputAssembly = $fullOutput
$compileParams.CompilerOptions = "/target:winexe"

$compileParams.ReferencedAssemblies.Add("System.dll")
$compileParams.ReferencedAssemblies.Add("System.Core.dll")
$compileParams.ReferencedAssemblies.Add("System.Windows.Forms.dll")
$compileParams.ReferencedAssemblies.Add("System.Drawing.dll")

$smaAssembly = [System.Reflection.Assembly]::GetAssembly([System.Management.Automation.PowerShell])
if ($smaAssembly) {
    $compileParams.ReferencedAssemblies.Add($smaAssembly.Location)
} else {
    $compileParams.ReferencedAssemblies.Add("System.Management.Automation.dll")
}

$results = $codeProvider.CompileAssemblyFromSource($compileParams, $cSharpCode)

if ($results.Errors.Count -gt 0) {
    foreach ($err in $results.Errors) {
        Write-Host "Error: $err" -ForegroundColor Red
    }
    throw "Falló la compilación a ejecutable."
} else {
    Write-Host "¡Compilación completada con éxito!" -ForegroundColor Green
    Write-Host "Ejecutable listo en: $fullOutput" -ForegroundColor White
}
