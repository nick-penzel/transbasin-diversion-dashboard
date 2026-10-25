## Goal
The ultimate goal of this module is to trial-run an irrigation consumptive use data model for a select basin at the HUC 8 scale. For this work, we will use the Roaring Fork River basin (HUC8 14010004). The goal is to show how much water was consumptively used through irrigation. This means ETa should focus on the irrigation season and should be compared to a baseline non-irrigated ETa at the HUC8 scale. The temporal grain for this module is at the water year scale, and should focus on the last complete wyear (currently 2026)
## Workflow
This represents a new stage of the project because this module requires significant data and modeling development beyond a simple ETL pipeline and visualization. Because of this, the module and future similar ones will begin with a QMD investigation and walkthrough of the methods for me and others to review. Eventually, we'll turn these QMDS into a bookdown or something similar and publish it alongside the dashboard as a methodology.

To start, once you have read this document, conduct a basic literature and methods review to find resources and papers that could benefit and inform our goals. These should be written into a folder methods.md to be used for AI agents working in this folder. The methods should include APA citations so that the QMD can correctly cite the relevant info. Once the review is finished, come back to me with a proposed method before you start the QMD investigation.

Once the QMD is finished, it should be passed to a sub-agent for a code review to ensure the ETL pipelines created in the investigation are valid; then another hydrologist agent should review it for scientific validity. 

Once the investigation is finished, elevate it to me for review. After I review, we can elevate the needed ETL and storage to S3, branch the dashboard, test the deployment and visuals, and then open a PR to main and deployment. The new dashboard element will eventually live in its own tab in deployment. 

Maintain a folder-specific CLAUDE.md for this module that includes the current needed context; refer to this playbook as the overarching goals and the CLAUDE.md as the project specifics. Broad methodology and scientific context go into the methods.md
### Data and modeling 
This is my rough conceptual sketch as a starting point, but don't let it limit the investigation. The actual model will change as the review and investigation develop. Sourcing RS ETa may require using Google Earth Engine or some other cloud computing provider. 

Possible Data sources:
The CDSS irrigated fields 
Open ET and other remote-sensed ETa 
GridMET ETo

The old repo located here: /Users/nickpenzel/Documents/R Projects/GitHub_Repo/Ag_waterefficiency may have some useful scripts for interacting with CDSS and data sources. 
## In the future 
I will want to incorporate CDSS diversion and water rights data to attempt to show which users and uses are using water for the test HUC8  