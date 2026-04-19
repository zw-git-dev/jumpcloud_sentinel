# Azure Sentinel Data Connector for JumpCloud SSO event logs

This Azure Function App will connect to the JumpCloud Rest-API using your JumpCloud api Token and retrieve the event logs and ingest them into a custom table called "JumpCloud" in your Log Anaytics Workspace used by Azure Sentinel.


The Azure Function has bee setup to trigger once every 5 minutes and trigger a seperate execution for each log type listed in the configuration you setup. 

### Prerequisites
Before deplying this Arm Template 
1. Decide which of the JumpCloud logs you want to ingest into Azure Sentinel, details on the log types available are found in their documentation [**here**](https://jumpcloud-insights.api-docs.io/1.0/how-to-use-the-directory-insights-api/json-post-request-body). You can choose any combination of event type for ingestion **However Do not mix 'ALL' type with any other or duplicate events will be ingested.**
2. You may need a JumpCloud license that enables Directory Insights to be able to access the Rest-API.
3. Follow the instructions on the [JumpCloud docs](https://jumpcloud-insights.api-docs.io/1.0/authentication-and-authorization/authentication) on how to access your API Key.
4. You will need your WorkspaceID and WorkspaceKey for the Log Analytics Workspace you want the logs to be ingested into.
5. You will also need your JumpCloud Organization ID obtained from Jump Cloud console > Settings > Organization Profile > Copy Organization ID

6. The person deploying the template must be allowed to **create role assignments** in the target resource group or subscription (for example **Owner** or **User Access Administrator** on the subscription or resource group), because the deployment grants a managed identity permission to publish the function package.

**NOTE:** There maybe additional charges incurred on your Azure Subscription if you run this Azure Function

#### Deployment
The simplest way to deploy is to launch the Deployment template from the Deploy to [**Azure Button below**]

**NOTES:** 
1. Where possible details in the Deployment Template have been prepopulated.
2. The function name needs to be globally unique, a random character generator will generate several charactors to append to your entered name. Be aware that this name is also used for the associated storage account so if your prefix is too long the template will fail validation becuase the name is longer than the permitted length for a storage Account Name.
3. Once successfully deployed the function will start triggering within 5 minutes and the inital request to JumpCloud will be for logs since the previous midnight UTC time. 

4. **Function code** is published **automatically** in the same deployment: a built-in job downloads the [default GitHub `main` branch zip](https://github.com/zw-git-dev/jumpcloud_sentinel/archive/refs/heads/main.zip), packages the `AzureFunctionJumpCloud` folder, uploads it to your storage account, and sets `WEBSITE_RUN_FROM_PACKAGE` to that blob. If you **fork** the repo, set template parameters **FunctionSourceArchiveUrl** and **DeploymentScriptUri** to your fork’s zip and raw script URL. To **refresh** the published code from GitHub on a later deploy, set **deploymentScriptForceUpdateTag** to a new value (e.g. a timestamp) and redeploy the template.

5. (Optional) For a local build without re-running the full ARM template, use `az login` and `.\scripts\Deploy-JumpCloudFunction.ps1` with your resource group and function app name.

**Role assignment / `RoleDefinitionDoesNotExist`:** The template parameter **ContributorRoleDefinitionGuid** must be the [Contributor](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#contributor) id ending in **`dd24c`** (not `dd247`). If you still see `dd247` in the error, Azure is using an **old copy** of the template—open the [raw JSON](https://raw.githubusercontent.com/zw-git-dev/jumpcloud_sentinel/main/azuredeploy_JumpCloud_API_FunctionApp.json), confirm `contentVersion` is **1.0.0.2** or later, then deploy again from that link or clear the portal’s custom deployment and re-paste the file.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fzw-git-dev%2Fjumpcloud_sentinel%2Fmain%2Fazuredeploy_JumpCloud_API_FunctionApp.json)

