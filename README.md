# Introduction

Welcome to the Azure to Azure Migration Toolkit repository! This toolkit is intended to facilitate migration of workloads between Azure regions. The initiative is based on the documentation provided in the [Move across regions](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/relocate-index) articles, which outline the process end to end, albeit with a lot of manual activities involved. The goal of this toolkit is to automate as much of the process as possible, making it easier for customers to migrate their workloads.

## Disclaimer

Please note that the tooling in this GitHub repository is currently in development and may be subject to frequent changes and updates. This means that the functionality and features of the tooling may change without notice. As such, you are advised to ensure that it is tested thoroughly in a test environment before considering moving to production.

We would love to hear feedback or questions regarding the tooling. To get in touch with us, feel free to create an issue [here](https://github.com/Azure/Azure2AzureTK/issues) and we will get back to you as soon as possible.  

By accessing or using the code in this repository, you agree to assume all risks associated with its use and to use it at your own discretion and risk. Microsoft shall not be liable for any damages or losses resulting from the use of this code. For support details, please see the [Support section](https://github.com/Azure/Azure2AzureTK/blob/main/SUPPORT.md).

## 📣Feedback 📣

If you have encountered an issue with Azure Baseline Alerts for ALZ, please see our [SUPPORT](https://github.com/Azure/Azure2AzureTK/blob/main/SUPPORT.md) page.

## Deployment Guide

We have a [User Guide](../../wiki/Introduction-to-azure2azure-migration-toolkit) available for guidance on how to consume the contents of this repo.

## Wiki

Please see the content in the [wiki](https://github.com/Azure/azure2azuretk/wiki) for more detailed information about the repo and various other pieces of documentation.

## Known Issues

Please see the [Known Issues](https://github.com/Azure/azure2azuretk/wiki/KnownIssues) in the wiki.

## Frequently Asked Questions

Please see the [Frequently Asked Questions](https://github.com/Azure/azure2azuretk/wiki/FAQ) in the wiki.

## Dependencies

The code in this repository is dependent on the following tools and libraries:
- PowerShell Core 7.5.1 or later
- Azure Powershell module Az.Monitor 5.2.2 or later
- Azure Powershell module Az.ResourceGraph 1.2.0 or later
- Azure Powershell module Az.Accounts 4.1.0 or later

If you experience any issues, please verify that you are at least on the minimum version of the dependencies listed above. If that is the case and you are still experiencing issues, please create an issue [here](https://github.com/Azure/Azure2AzureTK/issues) and we will get back to you as soon as possible

## Contributing

This project welcomes contributions and suggestions.
Most contributions require you to agree to a Contributor License Agreement (CLA)
declaring that you have the right to, and actually do, grant us the rights to use your contribution.
For details, visit [Contributor License Agreements](https://cla.opensource.microsoft.com).

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment).
Simply follow the instructions provided by the bot.
You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

> Details on contributing to this repo can be found [here in the wiki](https://github.com/azure/Azure2AzureTK/wiki/Contributing)

## Telemetry

When you leverage the IP located in this repo, Microsoft can identify the use of said IP. Microsoft collects this information to provide the best experiences with their products and to operate their business. The telemetry is collected through customer usage attribution. The data is collected and governed by [Microsoft's privacy policies](https://www.microsoft.com/trustcenter).

If you don't wish to send usage data to Microsoft, or need to understand more about its' use details can be found [here](https://github.com/azure/Azure2AzureTK/wiki/Telemetry).

## Trademarks

This project may contain trademarks or logos for projects, products, or services.
Authorized use of Microsoft trademarks or logos is subject to and must follow
[Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/legal/intellectualproperty/trademarks/usage/general).
Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.
Any use of third-party trademarks or logos are subject to those third-party's policies.
