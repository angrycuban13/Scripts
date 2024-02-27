#requires -Modules Microsoft.Graph.DeviceManagement,Microsoft.Graph.Groups

<#
.SYNOPSIS
    This script generates an Intune Assignment Report for a specific group.

.DESCRIPTION
    The script connects to Microsoft Graph and retrieves the Intune assignments for a specific group.
    The assignments are then converted to HTML and saved to a file. The file is then opened in the default browser.

.PARAMETER HtmlSavePath
    The path where the HTML file will be saved. If not provided, it defaults to the TEMP environment variable.

.EXAMPLE
    PS C:\> .\Get-IntuneAssignmentsForEntraIDGroup.ps1 -HtmlSavePath "C:\Reports"

    This command generates an Intune Assignment Report for a specific group and saves the HTML file to the "C:\Reports" directory.

.NOTES
    The script requires the Microsoft.Graph.DeviceManagement and Microsoft.Graph.Groups modules.
    It also requires the following permissions in Microsoft Graph: Group.Read.All, DeviceManagementManagedDevices.Read.All,
    DeviceManagementServiceConfig.Read.All, DeviceManagementApps.Read.All, DeviceManagementConfiguration.Read.All.

    The script will prompt for a group name and the types of policies to check.
    It will then retrieve the assignments for the selected policies and convert them to HTML.
    The HTML is saved to a file and the file is then opened in the default browser.

    .NOTES
   This script was made possible by the hard work of TimmyIT - https://timmyit.com/2023/10/09/get-all-assigned-intune-policies-and-apps-from-a-microsoft-entra-group/
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]
    $HtmlSavePath = "$env:TEMP"
)

function Show-SelectionScreen {

    <#
    .SYNOPSIS
        Displays a GUI window for the user to select a group name and policies to check.

    .DESCRIPTION
        The Show-SelectionScreen function displays a GUI window that allows the user to enter a group name and select which policies to check. The function returns a PSCustomObject that contains the group name and a hashtable of the selected policies.

    .PARAMETER None
        This function does not take any parameters.

    .EXAMPLE
        $selection = Show-SelectionScreen
        This example shows how to call the function and store the result in a variable.

    .INPUTS
        None. You cannot pipe objects to Show-SelectionScreen.

    .OUTPUTS
        PSCustomObject. The function returns a custom object that contains the group name and a hashtable of the selected policies.

    .NOTES
        The function uses WPF to create the GUI window. It also uses the PresentationFramework assembly, which is a part of .NET Framework.
    #>

    [CmdletBinding()]
    param ()

    begin {
        # Add the PresentationFramework assembly to access WPF classes
        Add-Type -AssemblyName PresentationFramework

        # XAML code for the window
        [xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Enter Group Name" Height="275" Width="450">
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Label Content="Group Name:" Grid.Row="0" Grid.Column="0" VerticalAlignment="Top" Grid.ColumnSpan="2" Margin="0,5,370,0" Grid.RowSpan="15"/>
        <TextBox x:Name="GroupNameTextBox" Grid.Row="0" Grid.Column="1" VerticalAlignment="Top" Margin="85,10,10,230" Grid.RowSpan="15"/>
        <Label Content="Select Which Intune Policies To Check:" Grid.Column="1" VerticalAlignment="Top" HorizontalAlignment="Center" Margin="0,33,0,0" Width="210"/>
        <CheckBox Name="SelectAllCheckBox" Content="Select All" Grid.Column="1" VerticalAlignment="Top" HorizontalAlignment="Left" Margin="120,60,0,0" IsChecked="False"/>
        <CheckBox Name="Applications" Content="Applications" Grid.Column="1" VerticalAlignment="Top" HorizontalAlignment="Left" Margin="120,75,0,0" IsChecked="False"/>
        <CheckBox Name="ApplicationConfigurations" Content="Application Configurations" Grid.Column="1" VerticalAlignment="Top" HorizontalAlignment="Left" Margin="120,90,0,0" IsChecked="False"/>
        <CheckBox Name="ApplicationProtectionPolicies" Content="Application Protection Policies" Grid.Column="1" VerticalAlignment="Top" HorizontalAlignment="Left" Margin="120,105,0,0" IsChecked="False"/>
        <CheckBox Name="DeviceCompliancePolicies" Content="Device Compliance Policies" Grid.Column="1" VerticalAlignment="Top" HorizontalAlignment="Left" Margin="120,120,0,0" IsChecked="False"/>
        <CheckBox Name="DeviceConfigurationPolicies" Content="Device Configuration Policies" Grid.Column="1" VerticalAlignment="Top" HorizontalAlignment="Left" Margin="120,135,0,0" IsChecked="False"/>
        <CheckBox Name="PlatformScripts" Content="Platform Scripts (Run Once Scripts)" Grid.Column="1" VerticalAlignment="Top" HorizontalAlignment="Left" Margin="120,150,0,0" IsChecked="False"/>
        <CheckBox Name="RemediationScripts" Content="Remediation Scripts" Grid.Column="1" VerticalAlignment="Top" HorizontalAlignment="Left" Margin="120,165,0,0" IsChecked="False"/>
        <CheckBox Name="WindowsAutoPilotProfiles" Content="Windows AutoPilot Profiles" Grid.Column="1" VerticalAlignment="Top" HorizontalAlignment="Left" Margin="120,180,0,0" IsChecked="False"/>
        <Button Name="OkButton" IsDefault="True" Content="OK" Width="50" Height="25" Grid.Column="1" HorizontalAlignment="Left" Margin="185,203,0,30"/>
    </Grid>
</Window>
'@

        # Create an empty PSCustomObject to store the results
        $result = [PSCustomObject]@{
            GroupName       = $null
            PoliciesToCheck = @{
                Applications                  = $false
                ApplicationConfigurations     = $false
                ApplicationProtectionPolicies = $false
                DeviceCompliancePolicies      = $false
                DeviceConfigurationPolicies   = $false
                PlatformScripts               = $false
                RemediationScripts            = $false
                WindowsAutoPilotProfiles      = $false
            }
        }
    }

    process {
        # Load the XAML code into a WPF window
        $reader = [System.Xml.XmlNodeReader]::new($xaml)
        $window = [Windows.Markup.XamlReader]::Load($reader)


        <# You can set a custom icon by uncomment the lines below and replacing the $iconBase64 variable with the base64 string of the icon you want to use. You can use https://www.base64-image.de/ to convert an image to a base64 string.

        # Base64 string of the icon
        $iconBase64 = ''

        # Convert the base64 string to bytes
        $iconBytes = [Convert]::FromBase64String($iconBase64)

        # Check if the icon file already exists, if not, create it
        $iconPath = "$env:TEMP\icon.ico"

        if (-Not (Test-Path "$env:TEMP\icon.ico")) {
            # Write the bytes to an icon file
            [System.IO.File]::WriteAllBytes("$env:TEMP\icon.ico", $iconBytes)
        }

        # Set the icon of the window
        $window.Icon = $iconPath #>

        # Find the controls in the window
        $button = $window.FindName('OkButton')
        $textBox = $window.FindName('GroupNameTextBox')

        # Find the checkboxes in the window
        $selectAllCheckBox = $window.FindName('SelectAllCheckBox')
        $applicationsCheckbox = $window.FindName('Applications')
        $applicationConfigurationsCheckbox = $window.FindName('ApplicationConfigurations')
        $applicationProtectionPoliciesCheckbox = $window.FindName('ApplicationProtectionPolicies')
        $deviceCompliancePoliciesCheckbox = $window.FindName('DeviceCompliancePolicies')
        $deviceConfigurationPoliciesCheckbox = $window.FindName('DeviceConfigurationPolicies')
        $platformScriptsCheckbox = $window.FindName('PlatformScripts')
        $remediationScriptsCheckbox = $window.FindName('RemediationScripts')
        $windowsAutoPilotProfilesCheckbox = $window.FindName('WindowsAutoPilotProfiles')

        # Add an event handler for the SelectAllCheckBox
        $selectAllCheckBox.Add_Click({
                $applicationsCheckbox.IsChecked = $selectAllCheckBox.IsChecked
                $applicationConfigurationsCheckbox.IsChecked = $selectAllCheckBox.IsChecked
                $applicationProtectionPoliciesCheckbox.IsChecked = $selectAllCheckBox.IsChecked
                $deviceCompliancePoliciesCheckbox.IsChecked = $selectAllCheckBox.IsChecked
                $deviceConfigurationPoliciesCheckbox.IsChecked = $selectAllCheckBox.IsChecked
                $platformScriptsCheckbox.IsChecked = $selectAllCheckBox.IsChecked
                $remediationScriptsCheckbox.IsChecked = $selectAllCheckBox.IsChecked
                $windowsAutoPilotProfilesCheckbox.IsChecked = $selectAllCheckBox.IsChecked
            })

        # Add an event handler for the OK button
        $button.Add_Click({
                $checkBoxesArray = @($applicationsCheckbox, $applicationConfigurationsCheckbox, $applicationProtectionPoliciesCheckbox, $deviceCompliancePoliciesCheckbox, $deviceConfigurationPoliciesCheckbox, $platformScriptsCheckbox, $remediationScriptsCheckbox, $windowsAutoPilotProfilesCheckbox)

                $checkedCheckboxes = $checkBoxesArray | Where-Object { $_.IsChecked -eq $true }

                if ([string]::IsNullOrWhiteSpace($textBox.Text)) {
                    # Show a message box if the group name is empty
                    [System.Windows.MessageBox]::Show('Please enter a group name.', 'Error', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
                }
                elseif ($checkedCheckboxes.Count -eq 0) {
                    # Show a message box if no checkboxes are checked
                    [System.Windows.MessageBox]::Show('Please select at least one policy to check.', 'Error', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
                }
                else {
                    $window.DialogResult = $true
                    $window.Close()
                }
            })

        # Focus the textbox when the window is loaded
        $window.Add_Loaded({
                $textBox.Focus()
            })

        # Show the window
        $window.ShowDialog() | Out-Null

        # Set the GroupName property of the result object to the text in the textbox
        $result.GroupName = ($textBox.Text).Trim()

        # Check if the SelectAllCheckBox is not checked
        if ($selectAllCheckBox.IsChecked -eq $false) {
            # Check each individual checkbox
            if ($applicationsCheckbox.IsChecked -eq $true) {
                $result.PoliciesToCheck['Applications'] = $true
            }
            if ($applicationConfigurationsCheckbox.IsChecked -eq $true) {
                $result.PoliciesToCheck['ApplicationConfigurations'] = $true
            }
            if ($applicationProtectionPoliciesCheckbox.IsChecked -eq $true) {
                $result.PoliciesToCheck['ApplicationProtectionPolicies'] = $true
            }
            if ($deviceCompliancePoliciesCheckbox.IsChecked -eq $true) {
                $result.PoliciesToCheck['DeviceCompliancePolicies'] = $true
            }
            if ($deviceConfigurationPoliciesCheckbox.IsChecked -eq $true) {
                $result.PoliciesToCheck['DeviceConfigurationPolicies'] = $true
            }
            if ($platformScriptsCheckbox.IsChecked -eq $true) {
                $result.PoliciesToCheck['PlatformScripts'] = $true
            }
            if ($remediationScriptsCheckbox.IsChecked -eq $true) {
                $result.PoliciesToCheck['RemediationScripts'] = $true
            }
            if ($windowsAutoPilotProfilesCheckbox.IsChecked -eq $true) {
                $result.PoliciesToCheck['WindowsAutoPilotProfiles'] = $true
            }
        }
        else {
            # Set all the individual checkboxes to true
            $result.PoliciesToCheck = @{
                All = $true
            }
        }
    }

    end {
        # Return the result object
        [PSCustomObject]$result
    }
}

function Get-IntuneApplicationAssigments {

    <#
    .SYNOPSIS
    Retrieves the applications assigned to a specific group in Microsoft Intune.

    .DESCRIPTION
    The Get-IntuneApplicationAssignments function uses the Microsoft Graph API to retrieve the applications assigned to a specific group in Microsoft Intune.

    .PARAMETER Group
    The group for which to retrieve the assigned applications. This should be an object of type Microsoft.Graph.PowerShell.Models.MicrosoftGraphGroup.

    .PARAMETER GraphApiVersion
    The version of the Microsoft Graph API to use. The default is 'beta'.

    .EXAMPLE
    $group = Get-MgGroup -GroupId 'group-id'
    Get-IntuneApplicationAssignments -Group $group

    This example retrieves the applications assigned to the group with the ID 'group-id'.
    #>

    [CmdletBinding()]
    param (
        # The group for which to retrieve the assigned applications
        [Parameter(Mandatory = $true, Position = 0)]
        [Microsoft.Graph.PowerShell.Models.MicrosoftGraphGroup]
        $Group,

        # The version of the Microsoft Graph API to use
        [Parameter(Mandatory = $false)]
        [string]
        $GraphApiVersion = 'beta'
    )

    begin {
        # Set the base URI and endpoints for the Microsoft Graph API
        $uri = "https://graph.microsoft.com/$graphApiVersion/deviceAppManagement/mobileApps"

        # Create an empty object to store the assignments
        $assignmentList = [System.Collections.Generic.List[PSCustomObject]]::new()
    }

    process {
        # Output a verbose message indicating which group's applications are being retrieved
        Write-Verbose "Retrieving applications assigned to group `"$($group.DisplayName)`""

        # Retrieve the applications assigned to the group
        $applicationAssignments = (Invoke-MgGraphRequest -Method Get -Uri "$uri/?`$expand=Assignments").Value | Where-Object { $_.assignments.target.groupId -match $group.id }

        # If no applications are assigned, add a custom object to the list
        if ($null -eq $applicationAssignments) {
            $applicationAssignmentObject = [PSCustomObject]@{
                DisplayName  = 'No applications assigned'
                LastModified = $null
            }

            $assignmentList.Add($applicationAssignmentObject)
        }

        # Add each application assignment to the list
        else {
            foreach ($assignment in $applicationAssignments) {
                $applicationAssignmentObject = [PSCustomObject]@{
                    DisplayName  = $assignment.DisplayName
                    LastModified = $assignment.lastModifiedDateTime
                }

                $assignmentList.Add($applicationAssignmentObject)
            }
        }
    }

    end {
        # Return the list of assignments
        $assignmentList
    }
}

function Get-IntuneApplicationConfigurationAssignments {

    <#
    .SYNOPSIS
        Retrieves the application configurations assigned to a specific group in Microsoft Intune.

    .DESCRIPTION
        The Get-IntuneApplicationConfigurationAssignments function uses the Microsoft Graph API to retrieve the application configurations assigned to a specific group in Microsoft Intune.

    .PARAMETER Group
        The group for which to retrieve the assigned application configurations. This should be an object of type Microsoft.Graph.PowerShell.Models.MicrosoftGraphGroup.

    .PARAMETER GraphApiVersion
        The version of the Microsoft Graph API to use. The default is 'beta'.

    .EXAMPLE
        $group = Get-MgGroup -GroupId 'group-id'
        Get-IntuneApplicationConfigurationAssignments -Group $group

        This example retrieves the application configurations assigned to the group with the ID 'group-id'.
    #>

    [CmdletBinding()]
    param (
        # The group for which to retrieve the assigned application configurations
        [Parameter(Mandatory = $true, Position = 0)]
        [Microsoft.Graph.PowerShell.Models.MicrosoftGraphGroup]
        $Group,

        # The version of the Microsoft Graph API to use
        [Parameter(Mandatory = $false)]
        [string]
        $GraphApiVersion = 'beta'
    )

    begin {
        # Set the base URI and endpoints for the Microsoft Graph API
        $uri = "https://graph.microsoft.com/$graphApiVersion/deviceAppManagement/targetedManagedAppConfigurations"

        # Create an empty object to store the assignments
        $assignmentList = [System.Collections.Generic.List[PSCustomObject]]::new()
    }

    process {
        # Output a verbose message indicating which group's application configurations are being retrieved
        Write-Verbose "Retrieving application configurations assigned to `"$($group.DisplayName)`""

        # Retrieve the application configurations assigned to the group
        $applicationConfigurationAssignments = (Invoke-MgGraphRequest -Method Get -Uri "$uri/?`$expand=Assignments").Value | Where-Object { $_.assignments.target.groupId -match $group.id }

        # If no application configurations are assigned, add a custom object to the list
        if ($null -eq $applicationConfigurationAssignments) {
            $applicationConfigurationAssignmentObject = [PSCustomObject]@{
                DisplayName  = 'No application configurations assigned'
                LastModified = $null
            }

            $assignmentList.Add($applicationConfigurationAssignmentObject)
        }

        # Add each application configuration assignment to the list
        else {
            foreach ($assignment in $applicationConfigurationAssignments) {
                $applicationConfigurationAssignmentObject = [PSCustomObject]@{
                    DisplayName  = $assignment.DisplayName
                    LastModified = $assignment.lastModifiedDateTime
                }

                $assignmentList.Add($applicationConfigurationAssignmentObject)
            }
        }
    }

    end {
        # Return the list of assignments
        $assignmentList
    }
}

function Get-IntuneApplicationProtectionAssignments {

    <#
    .SYNOPSIS
        Retrieves the application protection policies assigned to a specific group in Microsoft Intune.

    .DESCRIPTION
        The Get-IntuneApplicationProtectionAssignments function uses the Microsoft Graph API to retrieve the application protection policies assigned to a specific group in Microsoft Intune.

    .PARAMETER Group
        The group for which to retrieve the assigned application protection policies. This should be an object of type Microsoft.Graph.PowerShell.Models.MicrosoftGraphGroup.

    .PARAMETER GraphApiVersion
        The version of the Microsoft Graph API to use. The default is 'beta'.

    .EXAMPLE
        $group = Get-MgGroup -GroupId 'group-id'
        Get-IntuneApplicationProtectionAssignments -Group $group

        This example retrieves the application protection policies assigned to the group with the ID 'group-id'.
    #>

    [CmdletBinding()]
    param (
        # The group for which to retrieve the assigned application protection policies
        [Parameter(Mandatory = $true, Position = 0)]
        [Microsoft.Graph.PowerShell.Models.MicrosoftGraphGroup]
        $Group,

        # The version of the Microsoft Graph API to use
        [Parameter(Mandatory = $false)]
        [string]
        $GraphApiVersion = 'beta'
    )

    begin {
        # Set the base URI for the Microsoft Graph API
        $uri = "https://graph.microsoft.com/$graphApiVersion"

        # Define the endpoints for different types of application protection policies
        $applicationProtectionPoliciesEndpoints = @{
            AndroidManagedAppProtections            = 'deviceAppManagement/androidManagedAppProtections'
            iOSManagedAppProtections                = 'deviceAppManagement/iosManagedAppProtections'
            MdmWindowsInformationProtectionPolicies = 'deviceAppManagement/mdmWindowsInformationProtectionPolicies'
            WindowsManagedAppProtections            = 'deviceAppManagement/windowsManagedAppProtections'
        }

        # Create an empty list to store the assignments
        $assignmentList = [System.Collections.Generic.List[PSCustomObject]]::new()
    }

    process {
        # Output a verbose message indicating which group's application protection policies are being retrieved
        Write-Verbose "Retrieving application protection policies assigned to `"$($group.DisplayName)`""

        # Iterate through each application protection policy endpoint
        foreach ($endpoint in $applicationProtectionPoliciesEndpoints.GetEnumerator()) {
            # Retrieve the application protection policies assigned to the group
            $applicationProtectionPolicyAssignments = (Invoke-MgGraphRequest -Method Get -Uri "$uri/$($endpoint.Value)?`$expand=Assignments").Value | Where-Object { $_.assignments.target.groupId -match $group.id }

            # If no application protection policies are assigned, add a custom object to the list
            if ($null -eq $applicationProtectionPolicyAssignments) {
                $applicationProtectionPolicyAssignmentObject = [PSCustomObject]@{
                    ApplicationProtectionPolicyPlatform = $endpoint.Key
                    DisplayName                         = 'No application protection policies assigned'
                    LastModified                        = $null
                }

                $assignmentList.Add($applicationProtectionPolicyAssignmentObject)
            }

            # Add each application protection policy assignment to the list
            else {
                foreach ($applicationProtectionPolicyAssignment in $applicationProtectionPolicyAssignments) {
                    $applicationProtectionPolicyAssignmentObject = [PSCustomObject]@{
                        ApplicationProtectionPolicyPlatform = $endpoint.Key
                        DisplayName                         = $applicationProtectionPolicyAssignment.DisplayName
                        LastModified                        = $applicationProtectionPolicyAssignment.lastModifiedDateTime
                    }

                    $assignmentList.Add($applicationProtectionPolicyAssignmentObject)
                }
            }
        }
    }

    end {
        # Return the list of assignments
        $assignmentList
    }
}

function Get-IntuneDeviceComplianceAssignments {

    <#
    .SYNOPSIS
        Retrieves the device compliance policies assigned to a specific group in Microsoft Intune.

    .DESCRIPTION
        The Get-IntuneDeviceComplianceAssignments function uses the Microsoft Graph API to retrieve the device compliance policies assigned to a specific group in Microsoft Intune.

    .PARAMETER Group
        The group for which to retrieve the assigned device compliance policies. This should be an object of type Microsoft.Graph.PowerShell.Models.MicrosoftGraphGroup.

    .PARAMETER GraphApiVersion
        The version of the Microsoft Graph API to use. The default is 'beta'.

    .EXAMPLE
        $group = Get-MgGroup -GroupId 'group-id'
        Get-IntuneDeviceComplianceAssignments -Group $group

        This example retrieves the device compliance policies assigned to the group with the ID 'group-id'.
    #>

    [CmdletBinding()]
    param (
        # The group for which to retrieve the assigned device compliance policies
        [Parameter(Mandatory = $true, Position = 0)]
        [Microsoft.Graph.PowerShell.Models.MicrosoftGraphGroup]
        $Group,

        # The version of the Microsoft Graph API to use
        [Parameter(Mandatory = $false)]
        [string]
        $GraphApiVersion = 'beta'
    )

    begin {
        # Set the base URI for the Microsoft Graph API
        $uri = "https://graph.microsoft.com/$graphApiVersion/deviceManagement/deviceCompliancePolicies"

        # Create an empty list to store the assignments
        $assignmentList = [System.Collections.Generic.List[PSCustomObject]]::new()
    }

    process {
        # Output a verbose message indicating which group's device compliance policies are being retrieved
        Write-Verbose "Retrieving device compliance policies assigned to `"$($group.DisplayName)`""

        # Retrieve the device compliance policies assigned to the group
        $deviceCompliancePoliciesAssignments = (Invoke-MgGraphRequest -Method Get -Uri "$uri/?`$expand=Assignments").Value | Where-Object { $_.assignments.target.groupId -match $group.id }

        # If no device compliance policies are assigned, add a custom object to the list
        if ($null -eq $deviceCompliancePoliciesAssignments) {
            $deviceCompliancePolicyAssignmentObject = [PSCustomObject]@{
                DisplayName  = 'No device compliance policies assigned'
                LastModified = $null
            }

            $assignmentList.Add($deviceCompliancePolicyAssignmentObject)
        }

        # Add each device compliance policy assignment to the list
        else {
            foreach ($assignment in $deviceCompliancePoliciesAssignments) {
                $deviceCompliancePolicyAssignmentObject = [PSCustomObject]@{
                    DisplayName  = $assignment.DisplayName
                    LastModified = $assignment.lastModifiedDateTime
                }

                $assignmentList.Add($deviceCompliancePolicyAssignmentObject)
            }
        }
    }

    end {
        # Return the list of assignments
        $assignmentList
    }
}

function Get-IntuneDeviceConfigurationAssignments {

    <#
    .SYNOPSIS
        Retrieves the device configuration policies assigned to a specific group in Microsoft Intune.

    .DESCRIPTION
        The Get-IntuneDeviceConfigurationAssignments function uses the Microsoft Graph API to retrieve the device configuration policies assigned to a specific group in Microsoft Intune.

    .PARAMETER Group
        The group for which to retrieve the assigned device configuration policies. This should be an object of type Microsoft.Graph.PowerShell.Models.MicrosoftGraphGroup.

    .PARAMETER GraphApiVersion
        The version of the Microsoft Graph API to use. The default is 'beta'.

    .EXAMPLE
        $group = Get-MgGroup -GroupId 'group-id'
        Get-IntuneDeviceConfigurationAssignments -Group $group

        This example retrieves the device configuration policies assigned to the group with the ID 'group-id'.
    #>

    [CmdletBinding()]
    param (
        # The group for which to retrieve the assigned device configuration policies
        [Parameter(Mandatory = $true, Position = 0)]
        [Microsoft.Graph.PowerShell.Models.MicrosoftGraphGroup]
        $Group,

        # The version of the Microsoft Graph API to use
        [Parameter(Mandatory = $false)]
        [string]
        $GraphApiVersion = 'beta'
    )

    begin {
        # Set the base URI for the Microsoft Graph API
        $uri = "https://graph.microsoft.com/$graphApiVersion"

        # Define the endpoints for different types of device configuration policies
        $deviceConfigurationPoliciesEndpoints = @{
            ConfigurationPolicies     = 'deviceManagement/configurationPolicies'
            DeviceConfigurations      = 'deviceManagement/deviceConfigurations'
            GroupPolicyConfigurations = 'deviceManagement/groupPolicyConfigurations'
            MobileAppConfigurations   = 'deviceAppManagement/mobileAppConfigurations'
        }

        # Create an empty list to store the assignments
        $assignmentList = [System.Collections.Generic.List[PSCustomObject]]::new()
    }

    process {
        # Output a verbose message indicating which group's device configuration policies are being retrieved
        Write-Verbose "Retrieving device configuration policies assigned to `"$($group.DisplayName)`""

        # Iterate through each device configuration policy endpoint
        foreach ($endpoint in $deviceConfigurationPoliciesEndpoints.GetEnumerator()) {
            # Retrieve the device configuration policies assigned to the group
            $deviceConfigurationPolicyAssignments = (Invoke-MgGraphRequest -Method Get -Uri "$uri/$($endpoint.Value)?`$expand=Assignments").Value | Where-Object { $_.assignments.target.groupId -match $group.id }

            # If no device configuration policies are assigned, add a custom object to the list
            if ($null -eq $deviceConfigurationPolicyAssignments) {
                $deviceConfigurationPolicyAssignmentObject = [PSCustomObject]@{
                    ConfigurationPolicyProvider = $endpoint.Key
                    DisplayName                 = 'No device configuration policies assigned'
                    LastModified                = $null
                }

                $assignmentList.Add($deviceConfigurationPolicyAssignmentObject)
            }

            # Add each device configuration policy assignment to the list
            else {
                foreach ($assignment in $deviceConfigurationPolicyAssignments) {
                    # ConfigurationPolicies does not contain DisplayName property
                    if ($null -eq $assignment.DisplayName) {
                        $deviceConfigurationDisplayName = $assignment.Name
                    }

                    else {
                        $deviceConfigurationDisplayName = $assignment.DisplayName
                    }

                    $deviceConfigurationPolicyAssignmentObject = [PSCustomObject]@{
                        ConfigurationPolicyProvider = $endpoint.Key
                        DisplayName                 = $deviceConfigurationDisplayName
                        LastModified                = $assignment.lastModifiedDateTime
                    }

                    $assignmentList.Add($deviceConfigurationPolicyAssignmentObject)
                }
            }
        }
    }

    end {
        # Return the list of assignments
        $assignmentList
    }
}

function Get-IntunePlatformScriptsAssignments {

    <#
    .SYNOPSIS
        Retrieves the platform scripts assigned to a specific group in Microsoft Intune.

    .DESCRIPTION
        The Get-IntunePlatformScriptsAssignments function uses the Microsoft Graph API to retrieve the platform scripts assigned to a specific group in Microsoft Intune.

    .PARAMETER Group
        The group for which to retrieve the assigned platform scripts. This should be an object of type Microsoft.Graph.PowerShell.Models.MicrosoftGraphGroup.

    .PARAMETER GraphApiVersion
        The version of the Microsoft Graph API to use. The default is 'beta'.

    .EXAMPLE
        $group = Get-MgGroup -GroupId 'group-id'
        Get-IntunePlatformScriptsAssignments -Group $group

        This example retrieves the platform scripts assigned to the group with the ID 'group-id'.
    #>

    [CmdletBinding()]
    param (
        # The group for which to retrieve the assigned platform scripts
        [Parameter(Mandatory = $true, Position = 0)]
        [Microsoft.Graph.PowerShell.Models.MicrosoftGraphGroup]
        $Group,

        # The version of the Microsoft Graph API to use
        [Parameter(Mandatory = $false)]
        [string]
        $GraphApiVersion = 'beta'
    )

    begin {
        # Set the base URI for the Microsoft Graph API
        $uri = "https://graph.microsoft.com/$graphApiVersion/deviceManagement/deviceManagementScripts"

        # Create an empty list to store the assignments
        $assignmentList = [System.Collections.Generic.List[PSCustomObject]]::new()
    }

    process {
        # Output a verbose message indicating which group's platform scripts are being retrieved
        Write-Verbose "Retrieving platform scripts assigned to `"$($group.DisplayName)`""

        # Retrieve all platform scripts
        $allPlatformScripts = Invoke-MgGraphRequest -Method Get -Uri $uri

        # Iterate through each platform script
        foreach ($platformScript in $allPlatformScripts) {
            # Retrieve the platform script assignments for the group
            $platformScriptAssignments = (Invoke-MgGraphRequest -Method Get -Uri "$uri/$($platfromScript.Id)?`$expand=Assignments").Value | Where-Object { $_.assignments.target.groupId -match $group.id }

            # If no platform scripts are assigned, add a custom object to the list
            if ($null -eq $platformScriptAssignments) {
                $platformScriptAssignmentObject = [PSCustomObject]@{
                    DisplayName  = 'No platform scripts assigned'
                    LastModified = $null
                }

                $assignmentList.Add($platformScriptAssignmentObject)
            }

            # Add each platform script assignment to the list
            else {
                foreach ($assignment in $platformScriptAssignments) {
                    $platformScriptAssignmentObject = [PSCustomObject]@{
                        DisplayName  = $assignment.DisplayName
                        LastModified = $assignment.lastModifiedDateTime
                    }

                    $assignmentList.Add($platformScriptAssignmentObject)
                }
            }
        }
    }

    end {
        # Return the list of assignments
        $assignmentList
    }
}

function Get-IntuneRemediationScriptsAssignments {

    <#
    .SYNOPSIS
        Retrieves the remediation scripts assigned to a specific group in Microsoft Intune.

    .DESCRIPTION
        The Get-IntuneRemediationScriptsAssignments function uses the Microsoft Graph API to retrieve the remediation scripts assigned to a specific group in Microsoft Intune.

    .PARAMETER Group
        The group for which to retrieve the assigned remediation scripts. This should be an object of type Microsoft.Graph.PowerShell.Models.MicrosoftGraphGroup.

    .PARAMETER GraphApiVersion
        The version of the Microsoft Graph API to use. The default is 'beta'.

    .EXAMPLE
        $group = Get-MgGroup -GroupId 'group-id'
        Get-IntuneRemediationScriptsAssignments -Group $group

        This example retrieves the remediation scripts assigned to the group with the ID 'group-id'.
    #>

    [CmdletBinding()]
    param (
        # The group for which to retrieve the assigned remediation scripts
        [Parameter(Mandatory = $true, Position = 0)]
        [Microsoft.Graph.PowerShell.Models.MicrosoftGraphGroup]
        $Group,

        # The version of the Microsoft Graph API to use
        [Parameter(Mandatory = $false)]
        [string]
        $GraphApiVersion = 'beta'
    )

    begin {
        # Set the base URI for the Microsoft Graph API
        $uri = "https://graph.microsoft.com/$graphApiVersion/deviceManagement/deviceHealthScripts"

        # Create an empty list to store the assignments
        $assignmentList = [System.Collections.Generic.List[PSCustomObject]]::new()
    }

    process {
        # Output a verbose message indicating which group's remediation scripts are being retrieved
        Write-Verbose "Retrieving remediation scripts assigned to `"$($group.DisplayName)`""

        # Retrieve all remediation scripts
        $allRemediationScripts = Invoke-MgGraphRequest -Method Get -Uri $uri

        # Iterate through each remediation script
        foreach ($remediationScript in $allRemediationScripts) {
            # Retrieve the remediation script assignments for the group
            $remediationScriptAssignments = (Invoke-MgGraphRequest -Method Get -Uri "$uri/$($remediationScript.Id)?`$expand=Assignments").Value | Where-Object { $_.assignments.target.groupId -match $group.id }

            # If no remediation scripts are assigned, add a custom object to the list
            if ($null -eq $remediationScriptAssignments) {
                $remediationScriptAssignmentObject = [PSCustomObject]@{
                    DisplayName  = 'No remediation scripts assigned'
                    LastModified = $null
                }

                $assignmentList.Add($remediationScriptAssignmentObject)
            }

            # Add each remediation script assignment to the list
            else {
                foreach ($assignment in $remediationScriptAssignments) {
                    $remediationScriptAssignmentObject = [PSCustomObject]@{
                        DisplayName  = $assignment.DisplayName
                        LastModified = $assignment.lastModifiedDateTime
                    }

                    $assignmentList.Add($remediationScriptAssignmentObject)
                }
            }
        }
    }

    end {
        # Return the list of assignments
        $assignmentList
    }
}

function Get-IntuneWindowsAutopilotDeploymentProfilesAssignments {

    <#
    .SYNOPSIS
        Retrieves the Windows Autopilot deployment profiles assigned to a specific group in Microsoft Intune.

    .DESCRIPTION
        The Get-IntuneWindowsAutopilotDeploymentProfilesAssignments function uses the Microsoft Graph API to retrieve the Windows Autopilot deployment profiles assigned to a specific group in Microsoft Intune.

    .PARAMETER Group
        The group for which to retrieve the assigned Windows Autopilot deployment profiles. This should be an object of type Microsoft.Graph.PowerShell.Models.MicrosoftGraphGroup.

    .PARAMETER GraphApiVersion
        The version of the Microsoft Graph API to use. The default is 'beta'.

    .EXAMPLE
        $group = Get-MgGroup -GroupId 'group-id'
        Get-IntuneWindowsAutopilotDeploymentProfilesAssignments -Group $group

        This example retrieves the Windows Autopilot deployment profiles assigned to the group with the ID 'group-id'.
    #>

    [CmdletBinding()]
    param (
        # The group for which to retrieve the assigned Windows Autopilot deployment profiles
        [Parameter(Mandatory = $true, Position = 0)]
        [Microsoft.Graph.PowerShell.Models.MicrosoftGraphGroup]
        $Group,

        # The version of the Microsoft Graph API to use
        [Parameter(Mandatory = $false)]
        [string]
        $GraphApiVersion = 'beta'
    )

    begin {
        # Set the base URI for the Microsoft Graph API
        $uri = "https://graph.microsoft.com/$graphApiVersion/deviceManagement/windowsAutopilotDeploymentProfiles"

        # Create an empty list to store the assignments
        $assignmentList = [System.Collections.Generic.List[PSCustomObject]]::new()
    }

    process {
        # Output a verbose message indicating which group's Windows Autopilot deployment profiles are being retrieved
        Write-Verbose "Retrieving Windows Autopilot deployment profiles assigned to `"$($group.DisplayName)`""

        # Retrieve all Windows Autopilot deployment profiles
        $allDeploymentProfiles = Invoke-MgGraphRequest -Method Get -Uri $uri

        # If no Windows Autopilot deployment profiles are assigned, add a custom object to the list
        if ($null -eq $allDeploymentProfiles) {
            $deploymentProfileAssignmentObject = [PSCustomObject]@{
                DisplayName  = 'No Windows Autopilot deployment profiles found'
                LastModified = $null
            }

            $assignmentList.Add($deploymentProfileAssignmentObject)
        }

        else {
            # Iterate through each deployment profile
            foreach ($deploymentProfile in $allDeploymentProfiles) {
                # Retrieve the deployment profile assignments for the group
                $deploymentProfileAssignments = (Invoke-MgGraphRequest -Method Get -Uri "$uri/$($deploymentProfile.Id)?`$expand=Assignments").Value | Where-Object { $_.assignments.target.groupId -match $group.id }

                # If no deployment profiles are assigned, add a custom object to the list
                if ($null -eq $deploymentProfileAssignments) {
                    $deploymentProfileAssignmentObject = [PSCustomObject]@{
                        DisplayName  = 'No deployment profiles assigned'
                        LastModified = $null
                    }

                    $assignmentList.Add($deploymentProfileAssignmentObject)
                }

                # Add each deployment profile assignment to the list
                else {
                    foreach ($assignment in $deploymentProfileAssignments) {
                        $deploymentProfileAssignmentObject = [PSCustomObject]@{
                            DisplayName  = $assignment.DisplayName
                            LastModified = $assignment.lastModifiedDateTime
                        }

                        $assignmentList.Add($deploymentProfileAssignmentObject)
                    }
                }
            }
        }


    }

    end {
        # Return the list of assignments
        $assignmentList
    }
}

#If no existing connection to Microsoft Graph, connect to Microsoft Graph
if ($null -eq (Get-MgContext)) {
    Write-Verbose 'No existing connection to Microsoft Graph. Connecting to Microsoft Graph.'

    Connect-MgGraph -Scopes Group.Read.All, DeviceManagementManagedDevices.Read.All, DeviceManagementServiceConfig.Read.All, DeviceManagementApps.Read.All, DeviceManagementConfiguration.Read.All -NoWelcome
}

# Create the folder to save the CSV files
if (-Not (Test-Path $htmlSavePath)) {
    New-Item -ItemType Directory -Path $htmlSavePath | Out-Null
}

# Show the selection screen and store the result in a variable
$selection = Show-SelectionScreen

# Get the group object from Microsoft Graph
$group = Get-MgGroup -Filter "DisplayName eq '$($selection.GroupName)'"

# Throw an error if the group does not exist
if ($null -eq $group) {
    throw "Group `"$($selection.GroupName)`" not found. Please enter a valid group name."
}

# Create the HTML header
$htmlHeaderStyle = @'
<style>
    h1 {
        font-family: Arial, Helvetica, sans-serif;
        color: #00325b;
        font-size: 18px;
    }

    h2 {
        font-family: Arial, Helvetica, sans-serif;
        color: #f44b00;
        font-size: 16px;
    }

    table {
        font-size: 12px;
        border: 0px;
        font-family: Arial, Helvetica, sans-serif;
    }

    td {
        padding: 4px;
        margin: 0px;
        border: 0;
    }

    th {
        background: #005091;
        color: #fff;
        font-size: 10px;
        text-transform: uppercase;
        padding: 10px 15px;
        vertical-align: middle;
	}

    tbody tr:nth-child(even) {
        background: #f2f2f2;
    }

    tbody tr:nth-child(odd) {
        background: #ffffff;
    }

    .NormalUsage {
        color: #008000;
    }

    .WarningUsage {
        color: #ff5722
    }

    .CriticalUsage {
        color: #ff0000;
    }
</style>
'@

# Create the HTML string
$html = @"
<html>
<head>
$htmlHeaderStyle
</head>
<body>
    <h1>Intune Assignment Report - $($group.DisplayName) - $(Get-Date -UFormat %Y-%m-%d)</h1>
"@

# Filter which policies to check
$policiesToCheck = $selection.PoliciesToCheck.GetEnumerator() | Where-Object { $_.Value -eq $true } | Sort-Object -Property Key

# If the user selects all policies, add all the assignments to the HTML
if ($policiesToCheck.Name -eq 'All') {

    # Retrieve the application assignments for the group
    $applicationAssignments = Get-IntuneApplicationAssigments -Group $group
    # Convert the application assignments to HTML and add them to the HTML string
    $html += $applicationAssignments | ConvertTo-Html -PreContent '<h2>Application Assignments</h2>' -Fragment

    # Retrieve the application configuration assignments for the group
    $applicationConfigurationsAssignments = Get-IntuneApplicationConfigurationAssignments -Group $group
    # Convert the application configuration assignments to HTML and add them to the HTML string
    $html += $applicationConfigurationsAssignments | ConvertTo-Html -PreContent '<h2>Application Configuration Assignments</h2>' -Fragment

    # Retrieve the application protection assignments for the group
    $applicationProtectionAssignments = Get-IntuneApplicationProtectionAssignments -Group $group
    # Sort the application protection assignments by platform
    $applicationProtectionAssignmentsSorted = $applicationProtectionAssignments | Sort-Object -Property ApplicationProtectionPolicyPlatform

    # Convert the application protection assignments to HTML and add them to the HTML string
    $html += $applicationProtectionAssignmentsSorted | ConvertTo-Html -PreContent '<h2>Application Protection Assignments</h2>' -Fragment
    # Retrieve the device compliance assignments for the group
    $deviceComplianceAssignments = Get-IntuneDeviceComplianceAssignments -Group $group
    # Convert the device compliance assignments to HTML and add them to the HTML string
    $html += $deviceComplianceAssignments | ConvertTo-Html -PreContent '<h2>Device Compliance Assignments</h2>' -Fragment

    # Retrieve the device configuration assignments for the group
    $deviceConfigurationAssignments = Get-IntuneDeviceConfigurationAssignments -Group $group
    # Sort the device configuration assignments by provider
    $deviceConfigurationAssignmentsSorted = $deviceConfigurationAssignments | Sort-Object -Property ConfigurationPolicyProvider
    # Convert the device configuration assignments to HTML and add them to the HTML string
    $html += $deviceConfigurationAssignmentsSorted | ConvertTo-Html -PreContent '<h2>Device Configuration Assignments</h2>' -Fragment

    # Retrieve the platform scripts assignments for the group
    $platformScriptsAssignments = Get-IntunePlatformScriptsAssignments -Group $group
    # Convert the platform scripts assignments to HTML and add them to the HTML string
    $html += $platformScriptsAssignments | ConvertTo-Html -PreContent '<h2>Platform Scripts Assignments</h2>' -Fragment

    # Retrieve the remediation scripts assignments for the group
    $remediationScriptsAssignments = Get-IntuneRemediationScriptsAssignments -Group $group
    # Convert the remediation scripts assignments to HTML and add them to the HTML string
    $html += $remediationScriptsAssignments | ConvertTo-Html -PreContent '<h2>Remediation Scripts Assignments</h2>' -Fragment

    # Retrieve the Windows AutoPilot deployment profiles assignments for the group
    $windowsAutoPilotProfilesAssignments = Get-IntuneWindowsAutopilotDeploymentProfilesAssignments -Group $group
    # Convert the Windows AutoPilot deployment profiles assignments to HTML and add them to the HTML string
    $html += $windowsAutoPilotProfilesAssignments | ConvertTo-Html -PreContent '<h2>Windows AutoPilot Deployment Profiles Assignments</h2>' -Fragment
}

# If the user selects specific policies, add only the selected assignments to the HTML
else {
    Write-Verbose "Reviewing the following policies for group `"$($group.DisplayName)`":`n$($policiesToCheck.Name -join "`n")"

    if ($policiesToCheck.Key -eq 'Applications') {
        # Retrieve the application assignments for the group
        $applicationAssignments = Get-IntuneApplicationAssigments -Group $group

        # Convert the application assignments to HTML and add them to the HTML string
        $html += $applicationAssignments | ConvertTo-Html -PreContent '<h2>Application Assignments</h2>' -Fragment
    }

    if ($policiesToCheck.Key -eq 'ApplicationConfigurations') {
        # Retrieve the application configuration assignments for the group
        $applicationConfigurationsAssignments = Get-IntuneApplicationConfigurationAssignments -Group $group

        # Convert the application configuration assignments to HTML and add them to the HTML string
        $html += $applicationConfigurationsAssignments | ConvertTo-Html -PreContent '<h2>Application Configuration Assignments</h2>' -Fragment
    }

    if ($policiesToCheck.Key -eq 'ApplicationProtectionPolicies') {
        # Retrieve the application protection assignments for the group
        $applicationProtectionAssignments = Get-IntuneApplicationProtectionAssignments -Group $group

        # Sort the application protection assignments by platform
        $applicationProtectionAssignmentsSorted = $applicationProtectionAssignments | Sort-Object -Property ApplicationProtectionPolicyPlatform

        # Convert the application protection assignments to HTML and add them to the HTML string
        $html += $applicationProtectionAssignmentsSorted | ConvertTo-Html -PreContent '<h2>Application Protection Assignments</h2>' -Fragment
    }

    if ($policiesToCheck.Key -eq 'DeviceCompliancePolicies') {
        # Retrieve the device compliance assignments for the group
        $deviceComplianceAssignments = Get-IntuneDeviceComplianceAssignments -Group $group

        # Convert the device compliance assignments to HTML and add them to the HTML string
        $html += $deviceComplianceAssignments | ConvertTo-Html -PreContent '<h2>Device Compliance Assignments</h2>' -Fragment
    }

    if ($policiesToCheck.Key -eq 'DeviceConfigurationPolicies') {
        # Retrieve the device configuration assignments for the group
        $deviceConfigurationAssignments = Get-IntuneDeviceConfigurationAssignments -Group $group

        # Sort the device configuration assignments by provider
        $deviceConfigurationAssignmentsSorted = $deviceConfigurationAssignments | Sort-Object -Property ConfigurationPolicyProvider

        # Convert the device configuration assignments to HTML and add them to the HTML string
        $html += $deviceConfigurationAssignmentsSorted | ConvertTo-Html -PreContent '<h2>Device Configuration Assignments</h2>' -Fragment
    }

    if ($policiesToCheck.Key -eq 'PlatformScripts') {
        # Retrieve the platform scripts assignments for the group
        $platformScriptsAssignments = Get-IntunePlatformScriptsAssignments -Group $group

        # Convert the platform scripts assignments to HTML and add them to the HTML string
        $html += $platformScriptsAssignments | ConvertTo-Html -PreContent '<h2>Platform Scripts Assignments</h2>' -Fragment
    }

    if ($policiesToCheck.Key -eq 'RemediationScripts') {
        # Retrieve the remediation scripts assignments for the group
        $remediationScriptsAssignments = Get-IntuneRemediationScriptsAssignments -Group $group

        # Convert the remediation scripts assignments to HTML and add them to the HTML string
        $html += $remediationScriptsAssignments | ConvertTo-Html -PreContent '<h2>Remediation Scripts Assignments</h2>' -Fragment
    }

    if ($policiesToCheck.Key -eq 'WindowsAutoPilotProfiles') {
        # Retrieve the Windows AutoPilot deployment profiles assignments for the group
        $windowsAutoPilotProfilesAssignments = Get-IntuneWindowsAutopilotDeploymentProfilesAssignments -Group $group

        # Convert the Windows AutoPilot deployment profiles assignments to HTML and add them to the HTML string
        $html += $windowsAutoPilotProfilesAssignments | ConvertTo-Html -PreContent '<h2>Windows AutoPilot Deployment Profiles Assignments</h2>' -Fragment
    }
}

# Add the HTML footer
$html += '</body></html>'

# Save the HTML to a file and open it
$htmlFileName = Join-Path -Path $htmlSavePath -ChildPath "IntuneAssignments_$($group.DisplayName).html"
$html | Out-File -FilePath $htmlFileName
Invoke-Item $htmlFileName

# Disconnect from Microsoft Graph
Disconnect-MgGraph
