package tracing

import (
	"context"

	kubeclient "knative.dev/pkg/client/injection/kube/client"
	"knative.dev/pkg/logging"
	"knative.dev/pkg/test/zipkin"
	"knative.dev/reconciler-test/pkg/environment"
	"knative.dev/reconciler-test/pkg/knative"
)

func WithZipkin(ctx context.Context, env environment.Environment) (context.Context, error) {
	err := zipkin.SetupZipkinTracingFromConfigTracing(ctx,
		kubeclient.Get(ctx),
		logging.FromContext(ctx).Infof,
		knative.KnativeNamespaceFromContext(ctx))
	zipkin.ZipkinTracingEnabled = true
	return ctx, err
}
