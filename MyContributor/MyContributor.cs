using Microsoft.SqlServer.Dac.Deployment;
using Microsoft.SqlServer.Dac.Extensibility;

namespace Contributors;

[ExportDeploymentPlanModifier("MyDeploymentContributor", "1.0.0.0")]
public class MyDeploymentContributor : DeploymentPlanModifier
{
    protected override void OnExecute(DeploymentPlanContributorContext context)
    {
        Console.WriteLine("Hello world");
    }
}
