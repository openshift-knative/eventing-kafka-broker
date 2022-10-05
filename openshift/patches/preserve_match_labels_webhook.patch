diff --git a/vendor/knative.dev/pkg/webhook/helper.go b/vendor/knative.dev/pkg/webhook/helper.go
index cbcbb58c..df6b79f5 100644
--- a/vendor/knative.dev/pkg/webhook/helper.go
+++ b/vendor/knative.dev/pkg/webhook/helper.go
@@ -34,16 +34,13 @@ func EnsureLabelSelectorExpressions(
 		return want
 	}
 
-	if len(current.MatchExpressions) == 0 {
-		return want
-	}
-
 	var wantExpressions []metav1.LabelSelectorRequirement
 	if want != nil {
 		wantExpressions = want.MatchExpressions
 	}
 
 	return &metav1.LabelSelector{
+		MatchLabels: current.MatchLabels,
 		MatchExpressions: ensureLabelSelectorRequirements(
 			current.MatchExpressions, wantExpressions),
 	}
