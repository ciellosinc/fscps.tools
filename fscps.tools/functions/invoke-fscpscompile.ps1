
<#
    .SYNOPSIS
        Invoke the D365FSC models compilation
        
    .DESCRIPTION
        Invoke the D365FSC models compilation
        
    .PARAMETER Version
        The version of the D365FSC used to build
        
    .PARAMETER SourcesPath
        The folder contains a metadata files with binaries
        
    .PARAMETER BuildFolderPath
        The destination build folder
        
    .PARAMETER Force
        Cleanup destination build folder befor build
        
    .EXAMPLE
        PS C:\> Invoke-FSCPSCompile -Version "10.0.39"

        Example output:

        msMetadataDirectory  : D:\a\8\s\Metadata
        msFrameworkDirectory : C:\temp\buildbuild\packages\Microsoft.Dynamics.AX.Platform.CompilerPackage.7.0.7120.99
        msOutputDirectory    : C:\temp\buildbuild\bin
        solutionFolderPath   : C:\temp\buildbuild\10.0.39_build
        nugetPackagesPath    : C:\temp\buildbuild\packages
        buildLogFilePath     : C:\Users\VssAdministrator\AppData\Local\Temp\Build.sln.msbuild.log
        PACKAGE_NAME         : MAIN TEST-DeployablePackage-10.0.39-78
        PACKAGE_PATH         : C:\temp\buildbuild\artifacts\MAIN TEST-DeployablePackage-10.0.39-78.zip
        ARTIFACTS_PATH       : C:\temp\buildbuild\artifacts
        ARTIFACTS_LIST       : ["C:\temp\buildbuild\artifacts\MAIN TEST-DeployablePackage-10.0.39-78.zip"]

        This will build D365FSC package with version "10.0.39" to the Temp folder
        
    .EXAMPLE
        PS C:\> Invoke-FSCPSCompile -Version "10.0.39" -Path "c:\Temp"
        
        Example output:

        msMetadataDirectory  : D:\a\8\s\Metadata
        msFrameworkDirectory : C:\temp\buildbuild\packages\Microsoft.Dynamics.AX.Platform.CompilerPackage.7.0.7120.99
        msOutputDirectory    : C:\temp\buildbuild\bin
        solutionFolderPath   : C:\temp\buildbuild\10.0.39_build
        nugetPackagesPath    : C:\temp\buildbuild\packages
        buildLogFilePath     : C:\Users\VssAdministrator\AppData\Local\Temp\Build.sln.msbuild.log
        PACKAGE_NAME         : MAIN TEST-DeployablePackage-10.0.39-78
        PACKAGE_PATH         : C:\temp\buildbuild\artifacts\MAIN TEST-DeployablePackage-10.0.39-78.zip
        ARTIFACTS_PATH       : C:\temp\buildbuild\artifacts
        ARTIFACTS_LIST       : ["C:\temp\buildbuild\artifacts\MAIN TEST-DeployablePackage-10.0.39-78.zip"]

        This will build D365FSC package with version "10.0.39" to the Temp folder
        
    .NOTES
        Author: Oleksandr Nikolaiev (@onikolaiev)
        
#>

function Invoke-FSCPSCompile {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingInvokeExpression", "")]
    [CmdletBinding()]
    param (
        [string] $Version,
        [Parameter(Mandatory = $true)]
        [string] $SourcesPath,
        [string] $BuildFolderPath = (Join-Path $script:DefaultTempPath _bld),
        [switch] $Force
    )

    BEGIN {
        Invoke-TimeSignal -Start
        try{
            $CMDOUT = @{
                Verbose = If ($PSBoundParameters.Verbose -eq $true) { $true } else { $false };
                Debug = If ($PSBoundParameters.Debug -eq $true) { $true } else { $false }
            }
            $responseObject = [Ordered]@{}
            Write-PSFMessage -Level Important -Message "//=============================== Reading current FSC-PS settings ================================//"
            $settings = Get-FSCPSSettings @CMDOUT
            if($Version -eq "")
            {
                $Version = $settings.buildVersion
            }
            if($Version -eq "")
            {
                throw "D365FSC Version should be specified."
            }
        # $settings | Select-PSFObject -TypeName "FSCPS.TOOLS.settings" "*"
            # Gather version info
            $versionData = Get-FSCPSVersionInfo -Version $Version @CMDOUT
            $PlatformVersion = $versionData.PlatformVersion
            $ApplicationVersion = $versionData.AppVersion

            $tools_package_name =  'Microsoft.Dynamics.AX.Platform.CompilerPackage.' + $PlatformVersion
            $plat_package_name =  'Microsoft.Dynamics.AX.Platform.DevALM.BuildXpp.' + $PlatformVersion
            $app_package_name =  'Microsoft.Dynamics.AX.Application.DevALM.BuildXpp.' + $ApplicationVersion
            $appsuite_package_name =  'Microsoft.Dynamics.AX.ApplicationSuite.DevALM.BuildXpp.' + $ApplicationVersion 

            $NuGetPackagesPath = (Join-Path $BuildFolderPath packages)
            $SolutionBuildFolderPath = (Join-Path $BuildFolderPath "$($Version)_build")
            $NuGetPackagesConfigFilePath = (Join-Path $SolutionBuildFolderPath packages.config)
            $NuGetConfigFilePath = (Join-Path $SolutionBuildFolderPath nuget.config)
            
            if(Test-Path "$($SourcesPath)/PackagesLocalDirectory")
            {
                $SourceMetadataPath = (Join-Path $($SourcesPath) "/PackagesLocalDirectory")
            }
            elseif(Test-Path "$($SourcesPath)/Metadata")
            {
                $SourceMetadataPath = (Join-Path $($SourcesPath) "/Metadata")
            }
            else {
                $SourceMetadataPath = $($SourcesPath)
            }
            
            $BuidPropsFile = (Join-Path $SolutionBuildFolderPath \Build\build.props)
            
            $msReferenceFolder = "$($NuGetPackagesPath)\$($app_package_name)\ref\net40;$($NuGetPackagesPath)\$($plat_package_name)\ref\net40;$($NuGetPackagesPath)\$($appsuite_package_name)\ref\net40;$($SourceMetadataPath);$($BuildFolderPath)\bin"
            $msBuildTasksDirectory = "$NuGetPackagesPath\$($tools_package_name)\DevAlm".Trim()
            $msMetadataDirectory = "$($SourceMetadataPath)".Trim()
            $msFrameworkDirectory = "$($NuGetPackagesPath)\$($tools_package_name)".Trim()
            $msReferencePath = "$($NuGetPackagesPath)\$($tools_package_name)".Trim()
            $msOutputDirectory = "$($BuildFolderPath)\bin".Trim()     

            $responseObject.msMetadataDirectory = $msMetadataDirectory
            $responseObject.msFrameworkDirectory = $msFrameworkDirectory
            $responseObject.msOutputDirectory = $msOutputDirectory


            Write-PSFMessage -Level Important -Message "//=============================== Getting the list of models to build ============================//"
            if($($settings.specifyModelsManually) -eq "true")
            {
                $mtdtdPath = ("$($SourcesPath)\$($settings.metadataPath)".Trim())
                $mdls = $($settings.models).Split(",")
                if($($settings.includeTestModel) -eq "true")
                {
                    $testModels = Get-FSCMTestModel -modelNames $($mdls -join ",") -metadataPath $mtdtdPath @CMDOUT
                    ($testModels.Split(",").ForEach({$mdls+=($_)}))
                }
                $models = $mdls -join ","
                $modelsToPackage = $models
            }
            else {
                $models = Get-FSCModelList -MetadataPath $SourceMetadataPath -IncludeTest:($settings.includeTestModel -eq 'true') @CMDOUT                
                $modelsToPackage = Get-FSCModelList -MetadataPath $SourceMetadataPath -IncludeTest:($settings.includeTestModel -eq 'true') -All @CMDOUT    
            }

            Write-PSFMessage -Level Important -Message "Models to build: $models"
            Write-PSFMessage -Level Important -Message "Models to package: $modelsToPackage"
        }
        catch {
            Write-PSFMessage -Level Host -Message "Something went wrong while compiling D365FSC package" -Exception $PSItem.Exception
            Stop-PSFFunction -Message "Stopping because of errors"
            return
        }
        finally{
            
        }
    }
    
    PROCESS {
        if (Test-PSFFunctionInterrupt) { return }
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        try {            
            if($Force)
            {
                Write-PSFMessage -Level Important -Message "//=============================== Cleanup build folder ===========================================//"
                Remove-Item $BuildFolderPath -Recurse -Force -ErrorAction SilentlyContinue
            }

            Write-PSFMessage -Level Important -Message "//=============================== Generate solution folder =======================================//"
            $null = Invoke-GenerateSolution -ModelsList $models -DynamicsVersion $Version -MetadataPath $SourceMetadataPath -SolutionFolderPath $BuildFolderPath @CMDOUT
            $responseObject.solutionFolderPath = Join-Path $BuildFolderPath "$($Version)_build"
            Write-PSFMessage -Level Important -Message "Generating complete"
    
            Write-PSFMessage -Level Important -Message "//=============================== Copy source files to the build folder ==========================//"            
            $null = Test-PathExists -Path $BuildFolderPath -Type Container -Create @CMDOUT
            $null = Test-PathExists -Path $SolutionBuildFolderPath -Type Container -Create @CMDOUT
            Copy-Item $SourcesPath\* -Destination $BuildFolderPath -Recurse -Force @CMDOUT
            #Copy-Item $SolutionBuildFolderPath -Destination $BuildFolderPath -Recurse -Force
            Write-PSFMessage -Level Important -Message "Copying complete"
    
            Write-PSFMessage -Level Important -Message "//=============================== Download NuGet packages ========================================//"
            if($settings.useLocalNuGetStorage)
            {
                $null = Test-PathExists -Path $NuGetPackagesPath -Type Container -Create @CMDOUT
                $null = Get-FSCPSNuget -Version $PlatformVersion -Type PlatformCompilerPackage -Path $NuGetPackagesPath @CMDOUT
                $null = Get-FSCPSNuget -Version $PlatformVersion -Type PlatformDevALM -Path $NuGetPackagesPath @CMDOUT
                $null = Get-FSCPSNuget -Version $ApplicationVersion -Type ApplicationDevALM -Path $NuGetPackagesPath @CMDOUT
                $null = Get-FSCPSNuget -Version $ApplicationVersion -Type ApplicationSuiteDevALM -Path $NuGetPackagesPath @CMDOUT
            }
            Write-PSFMessage -Level Important -Message "NuGet`s downloading complete"
            $responseObject.nugetPackagesPath = $NuGetPackagesPath
            
            Write-PSFMessage -Level Important -Message "//=============================== Install NuGet packages ========================================//"
            #validata NuGet installation
            $nugetPath = Get-PSFConfigValue -FullName "fscps.tools.path.nuget"
            if(-not (Test-Path $nugetPath))
            {
                Install-FSCPSNugetCLI
            }
            ##update nuget config file
            $nugetNewContent = (Get-Content $NuGetConfigFilePath).Replace('c:\temp\packages', $NuGetPackagesPath)
            Set-Content $NuGetConfigFilePath $nugetNewContent
                
            $null = (& $nugetPath restore $NuGetPackagesConfigFilePath -PackagesDirectory $NuGetPackagesPath -ConfigFile $NuGetConfigFilePath)
            Write-PSFMessage -Level Important -Message "NuGet`s installation complete"

            Write-PSFMessage -Level Important -Message "//=============================== Copy binaries to the build folder =============================//"
            Copy-Filtered -Source $SourceMetadataPath -Target (Join-Path $BuildFolderPath bin) -Filter *.*
            Write-PSFMessage -Level Important -Message "Copying binaries complete"

            Write-PSFMessage -Level Important -Message "//=============================== Build solution ================================================//"
            Set-Content $BuidPropsFile (Get-Content $BuidPropsFile).Replace('ReferenceFolders', $msReferenceFolder)

            $msbuildresult = Invoke-MsBuild -Path (Join-Path $SolutionBuildFolderPath "\Build\Build.sln") -P "/p:BuildTasksDirectory=$msBuildTasksDirectory /p:MetadataDirectory=$msMetadataDirectory /p:FrameworkDirectory=$msFrameworkDirectory /p:ReferencePath=$msReferencePath /p:OutputDirectory=$msOutputDirectory" -ShowBuildOutputInCurrentWindow @CMDOUT

            $responseObject.buildLogFilePath = $msbuildresult.BuildLogFilePath

            if ($msbuildresult.BuildSucceeded -eq $true)
            {
                Write-PSFMessage -Level Host -Message ("Build completed successfully in {0:N1} seconds." -f $msbuildresult.BuildDuration.TotalSeconds)
            }
            elseif ($msbuildresult.BuildSucceeded -eq $false)
            {
               throw ("Build failed after {0:N1} seconds. Check the build log file '$($msbuildresult.BuildLogFilePath)' for errors." -f $msbuildresult.BuildDuration.TotalSeconds)
            }
            elseif ($null -eq $msbuildresult.BuildSucceeded)
            {
                throw "Unsure if build passed or failed: $($msbuildresult.Message)"
            }

            if($settings.generatePackages)
            {
                Write-PSFMessage -Level Important -Message "//=============================== Generate package ==============================================//"

                switch ($settings.namingStrategy) {
                    { $settings.namingStrategy -eq "Default" }
                    {
                        $packageNamePattern = $settings.packageNamePattern;
                        if($settings.packageName.Contains('.zip'))
                        {
                            $packageName = $settings.packageName
                        }
                        else {
                            $packageName = $settings.packageName + ".zip"
                        }
                        $packageNamePattern = $packageNamePattern.Replace("BRANCHNAME", $($settings.sourceBranch))
                        if($settings.deploy)
                        {
                            $packageNamePattern = $packageNamePattern.Replace("PACKAGENAME", $settings.azVMName)
                        }
                        else
                        {
                            $packageNamePattern = $packageNamePattern.Replace("PACKAGENAME", $packageName)
                        }
                        $packageNamePattern = $packageNamePattern.Replace("FNSCMVERSION", $DynamicsVersion)
                        $packageNamePattern = $packageNamePattern.Replace("DATE", (Get-Date -Format "yyyyMMdd").ToString())
                        
    
                        if($env:GITHUB_REPOSITORY)# If GitHub context
                        {
                            Write-PSFMessage -Level Verbose -Message "Running on GitHub"
                            $packageNamePattern = $packageNamePattern.Replace("RUNNUMBER", $ENV:GITHUB_RUN_NUMBER)
                        }
                        elseif($env:AGENT_ID)# If Azure DevOps context
                        {
                            Write-PSFMessage -Level Verbose -Message "Running on Azure"
                            $packageNamePattern = $packageNamePattern.Replace("RUNNUMBER", $ENV:Build_BuildNumber)
                
                        }
                        else { # If Desktop or other
                            Write-PSFMessage -Level Verbose -Message "Running on desktop"
                            $packageNamePattern = $packageNamePattern.Replace("RUNNUMBER", "")
                        }  
                        $packageName = $packageNamePattern + ".zip"
                        break;
                    }
                    { $settings.namingStrategy -eq "Custom" }
                    {
                        if($settings.packageName.Contains('.zip'))
                        {
                            $packageName = $settings.packageName
                        }
                        else {
                            $packageName = $settings.packageName + ".zip"
                        }
                        
                        break;
                    }
                    Default {
                        $packageName = $settings.packageName
                        break;
                    }
                }             
                

                $xppToolsPath = $msFrameworkDirectory
                $xppBinariesPath = (Join-Path $($BuildFolderPath) bin)
                $xppBinariesSearch = $modelsToPackage
                if($settings.artifactsPath -eq "")
                {
                    $deployablePackagePath = Join-Path (Join-Path $BuildFolderPath $settings.artifactsFolderName) ($packageName)
                }
                else {
                    $deployablePackagePath = Join-Path $settings.artifactsPath ($packageName)
                }

                $artifactDirectory = [System.IO.Path]::GetDirectoryName($deployablePackagePath)
                if (!(Test-Path -Path $artifactDirectory))
                {
                    $null = [System.IO.Directory]::CreateDirectory($artifactDirectory)
                }



                if ($xppBinariesSearch.Contains(","))
                {
                    [string[]]$xppBinariesSearch = $xppBinariesSearch -split ","
                }

                $potentialPackages = Find-FSCPSMatch -DefaultRoot $xppBinariesPath -Pattern $xppBinariesSearch | Where-Object { (Test-Path -LiteralPath $_ -PathType Container) }
                $packages = @()
                if ($potentialPackages.Length -gt 0)
                {
                    Write-PSFMessage -Level Verbose -Message "Found $($potentialPackages.Length) potential folders to include:"
                    foreach($package in $potentialPackages)
                    {
                        $packageBinPath = Join-Path -Path $package -ChildPath "bin"
                        
                        # If there is a bin folder and it contains *.MD files, assume it's a valid X++ binary
                        try {
                            if ((Test-Path -Path $packageBinPath) -and ((Get-ChildItem -Path $packageBinPath -Filter *.md).Count -gt 0))
                            {
                                Write-PSFMessage -Level Verbose -Message $packageBinPath
                                Write-PSFMessage -Level Verbose -Message "  - $package"
                                $packages += $package
                            }
                        }
                        catch
                        {
                            Write-PSFMessage -Level Verbose -Message "  - $package (not an X++ binary folder, skip)"
                        }
                    }



                    Import-Module (Join-Path -Path $xppToolsPath -ChildPath "CreatePackage.psm1")
                    $outputDir = Join-Path -Path $BuildFolderPath -ChildPath ((New-Guid).ToString())
                    $tempCombinedPackage = Join-Path -Path $BuildFolderPath -ChildPath "$((New-Guid).ToString()).zip"
                    try
                    {
                        New-Item -Path $outputDir -ItemType Directory > $null
                        Write-PSFMessage -Level Verbose -Message "Creating binary packages"
                        Invoke-FSCAssembliesImport $xppToolsPath -Verbose
                        foreach($packagePath in $packages)
                        {
                            $packageName = (Get-Item $packagePath).Name
                            Write-PSFMessage -Level Verbose -Message "  - '$packageName'"
                            $version = ""
                            $packageDll = Join-Path -Path $packagePath -ChildPath "bin\Dynamics.AX.$packageName.dll"
                            if (Test-Path $packageDll)
                            {
                                $version = (Get-Item $packageDll).VersionInfo.FileVersion
                            }
                            if (!$version)
                            {
                                $version = "1.0.0.0"
                            }
                            $null = New-XppRuntimePackage -packageName $packageName -packageDrop $packagePath -outputDir $outputDir -metadataDir $xppBinariesPath -packageVersion $version -binDir $xppToolsPath -enforceVersionCheck $True
                        }

                        Write-PSFMessage -Level Verbose -Message "Creating deployable package"
                        Add-Type -Path "$xppToolsPath\Microsoft.Dynamics.AXCreateDeployablePackageBase.dll"
                        Write-PSFMessage -Level Verbose -Message "  - Creating combined metadata package"
                        $null = [Microsoft.Dynamics.AXCreateDeployablePackageBase.BuildDeployablePackages]::CreateMetadataPackage($outputDir, $tempCombinedPackage)
                        Write-PSFMessage -Level Verbose -Message "  - Creating merged deployable package"
                        $null = [Microsoft.Dynamics.AXCreateDeployablePackageBase.BuildDeployablePackages]::MergePackage("$xppToolsPath\BaseMetadataDeployablePackage.zip", $tempCombinedPackage, $deployablePackagePath, $true, [String]::Empty)
                        Write-PSFMessage -Level Verbose -Message "Deployable package '$deployablePackagePath' successfully created."

                        $pname = ($deployablePackagePath.SubString("$deployablePackagePath".LastIndexOf('\') + 1)).Replace(".zip","")
                    
                        if($settings.exportModel)
                        {
                            Write-Output "::group::Export axmodel file"
                            $models
                            if($models.Split(","))
                            {
                                
                                $models.Split(",") | ForEach-Object{
                                    Write-PSFMessage -Level Verbose -Message "Exporting $_ model..."
                                    $modelFilePath = Export-D365Model -Path $artifactDirectory -Model (Get-AXModelName -ModelName $_ -ModelPath $msMetadataDirectory)  -BinDir $msFrameworkDirectory -MetaDataDir $msMetadataDirectory
                                    $modelFile = Get-Item $modelFilePath.File
                                    Rename-Item $modelFile.FullName (($_)+($modelFile.Extension)) -Force
                                }
                            }
                            else {
                                Write-PSFMessage -Level Verbose -Message "Exporting $models model..."
                                $modelFilePath = Export-D365Model -Path $artifactDirectory -Model (Get-AXModelName -ModelName $models -ModelPath $msMetadataDirectory) -BinDir $msFrameworkDirectory -MetaDataDir $msMetadataDirectory
                                $modelFile = Get-Item $modelFilePath.File
                                Rename-Item $modelFile.FullName (($models)+($modelFile.Extension)) -Force
                            }
                        }

                        $responseObject.PACKAGE_NAME = $pname
                        $responseObject.PACKAGE_PATH = $deployablePackagePath
                        $responseObject.ARTIFACTS_PATH = $artifactDirectory
                        #Add-Content -Path $env:GITHUB_OUTPUT -Value "PACKAGE_NAME=$pname"
                        #Add-Content -Path $env:GITHUB_ENV -Value "PACKAGE_NAME=$pname"
                        #Add-Content -Path $env:GITHUB_OUTPUT -Value "PACKAGE_PATH=$deployablePackagePath"
                        #Add-Content -Path $env:GITHUB_ENV -Value "PACKAGE_PATH=$deployablePackagePath"
                        #Add-Content -Path $env:GITHUB_OUTPUT -Value "ARTIFACTS_PATH=$artifactDirectory"
                        #Add-Content -Path $env:GITHUB_ENV -Value "ARTIFACTS_PATH=$artifactDirectory"


                        $artifacts = Get-ChildItem $artifactDirectory
                        $artifactsList = $artifacts.FullName -join ","

                        if($artifactsList.Contains(','))
                        {
                            $artifacts = $artifactsList.Split(',') | ConvertTo-Json -compress
                        }
                        else
                        {
                            $artifacts = '["'+$($artifactsList).ToString()+'"]'

                        }

                        #Add-Content -Path $env:GITHUB_OUTPUT -Value "ARTIFACTS_LIST=$artifacts"
                        #Add-Content -Path $env:GITHUB_ENV -Value "ARTIFACTS_LIST=$artifacts"
                        $responseObject.ARTIFACTS_LIST = $artifacts
                        
                    }
                    catch {
                        throw $_.Exception.Message
                    }
                    finally
                    {
                        if (Test-Path -Path $outputDir)
                        {
                            Remove-Item -Path $outputDir -Recurse -Force
                        }
                        if (Test-Path -Path $tempCombinedPackage)
                        {
                            Remove-Item -Path $tempCombinedPackage -Force
                        }
                    }
                }
                else
                {
                    throw "No X++ binary package(s) found"
                }
            }
        }
        catch {
            Write-PSFMessage -Level Host -Message "Something went wrong while compiling D365FSC package" -Exception $PSItem.Exception
            Stop-PSFFunction -Message "Stopping because of errors" -EnableException $true
            return
        }
        finally{
            [PSCustomObject]$responseObject | Select-PSFObject -TypeName "FSCPS.TOOLS.Build" "*"
        }
    }
    END {
        Invoke-TimeSignal -End
    }
}