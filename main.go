package main

import (
	"context"
	"fmt"
	"net"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/oklog/run"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"k8s.io/klog/v2"
	k8sdeviceplugin "k8s.io/kubelet/pkg/apis/deviceplugin/v1beta1"
)

const (
	pluginName                = "simple-device-plugin"
	simpleDeviceID1           = "simple-device-id1"
	simpleDeviceID2           = "simple-device-id2"
	hostSimpleDeviceFilePath1 = "/dev/simple-device1"
	hostSimpleDeviceFilePath2 = "/dev/simple-device2"
	podSimpleDeviceFilePath1  = "/dev/simple-device1"
	podSimpleDeviceFilePath2  = "/dev/simple-device2"
	envSimpleDevice1          = "SIMPLE_DEVICE_1"
	envSimpleDevice2          = "SIMPLE_DEVICE_2"
	annotationSimpleDevice1    = "example.com/simple-device1"
	annotationSimpleDevice2    = "example.com/simple-device2"
)

type exampleDevicePlugin struct {
	k8sdeviceplugin.UnimplementedDevicePluginServer
}

// GetDevicePluginOptions always returns an empty response.
func (p *exampleDevicePlugin) GetDevicePluginOptions(_ context.Context, _ *k8sdeviceplugin.Empty) (*k8sdeviceplugin.DevicePluginOptions, error) {
	return &k8sdeviceplugin.DevicePluginOptions{}, nil
}

func (p *exampleDevicePlugin) ListAndWatch(empty *k8sdeviceplugin.Empty, stream k8sdeviceplugin.DevicePlugin_ListAndWatchServer) error {
	// Send an initial list of available devices.
	resp := &k8sdeviceplugin.ListAndWatchResponse{
		Devices: []*k8sdeviceplugin.Device{
			{
				ID:     simpleDeviceID1,
				Health: k8sdeviceplugin.Healthy,
			},
			{
				ID:     simpleDeviceID2,
				Health: k8sdeviceplugin.Healthy,
			},
		},
	}
	if err := stream.Send(resp); err != nil {
		return status.Errorf(codes.Unknown, "failed to send response: %v", err)
	}

	// Wait for the stream to be closed or cancelled.
	<-stream.Context().Done()

	return nil
}

func (p *exampleDevicePlugin) Allocate(ctx context.Context, req *k8sdeviceplugin.AllocateRequest) (*k8sdeviceplugin.AllocateResponse, error) {
	// Check that the requested devices are available.
	for _, req := range req.ContainerRequests {
		for _, id := range req.DevicesIDs {
			if id != simpleDeviceID1 && id != simpleDeviceID2 {
				return nil, status.Errorf(codes.NotFound, "requested device %s is not available", id)
			}
		}
	}

	// Return the allocated devices.
	resp := &k8sdeviceplugin.AllocateResponse{
		ContainerResponses: []*k8sdeviceplugin.ContainerAllocateResponse{},
	}
	for _, req := range req.ContainerRequests {
		containerResp := &k8sdeviceplugin.ContainerAllocateResponse{
			Envs: make(map[string]string, len(req.DevicesIDs)),
			Annotations: make(map[string]string, len(req.DevicesIDs)),
		}
		for _, id := range req.DevicesIDs {
			hostPath := ""
			containerPath := ""
			envKey := ""
			annotationKey := ""
			switch id {
			case simpleDeviceID1:
				hostPath = hostSimpleDeviceFilePath1
				containerPath = podSimpleDeviceFilePath1
				envKey = envSimpleDevice1
				annotationKey = annotationSimpleDevice1
			case simpleDeviceID2:
				hostPath = hostSimpleDeviceFilePath2
				containerPath = podSimpleDeviceFilePath2
				envKey = envSimpleDevice2
				annotationKey = annotationSimpleDevice2
			default:
				continue
			}

			// set the device file mappings from host to container. The mapped files
			// must be device files
			containerResp.Devices = append(containerResp.Devices, &k8sdeviceplugin.DeviceSpec{
				HostPath:      hostPath,
				ContainerPath: containerPath,
				Permissions:   "rw",
			})
			// set environment variables for container
			containerResp.Envs[envKey] = containerPath
			// set the annotations for the container
			containerResp.Annotations[annotationKey] = ""
		}
		resp.ContainerResponses = append(resp.ContainerResponses, containerResp)
	}
	return resp, nil
}

func main() {
	// Create a listener for the gRPC server.
	socketName := fmt.Sprintf("%s.sock", pluginName)
	pluginSocketPath := fmt.Sprintf("/var/lib/kubelet/device-plugins/%s", socketName)

	listener, err := net.Listen("unix", pluginSocketPath)
	if err != nil {
		klog.Error(err, "failed to listen on the socket", err)
		os.Exit(1)
	}

	// Create a new gRPC server and register our device plugin with it.
	server := grpc.NewServer()
	k8sdeviceplugin.RegisterDevicePluginServer(server, &exampleDevicePlugin{})

	var g run.Group

	g.Add(
		func() error {
			if err := server.Serve(listener); err != nil {
				return fmt.Errorf("gRPC server exited unexpectedly: %v", err)
			}
			return nil
		},
		func(error) {
			server.Stop()
		},
	)

	ctx, cancel := context.WithCancel(context.Background())
	g.Add(
		func() error {
			kubeletSock := "/var/lib/kubelet/device-plugins/kubelet.sock"
			conn, err := grpc.Dial(kubeletSock, grpc.WithInsecure(), grpc.WithBlock(),
				grpc.WithDialer(func(addr string, timeout time.Duration) (net.Conn, error) {
					return net.DialTimeout("unix", addr, timeout)
				}))
			if err != nil {
				return fmt.Errorf("failed to dial grpc: %v", err)
			}

			client := k8sdeviceplugin.NewRegistrationClient(conn)
			request := &k8sdeviceplugin.RegisterRequest{
				Version:      k8sdeviceplugin.Version,
				Endpoint:     socketName,
				ResourceName: "example.com/simple-device",
			}
			if _, err = client.Register(context.Background(), request); err != nil {
				return fmt.Errorf("failed to register to kubelet: %v", err)
			}

			conn.Close()
			<-ctx.Done()
			return nil
		},
		func(error) {
			os.Remove(pluginSocketPath)
			cancel()
		},
	)

	// Exit gracefully on SIGINT and SIGTERM.
	term := make(chan os.Signal, 1)
	signal.Notify(term, syscall.SIGINT, syscall.SIGTERM)
	g.Add(
		func() error {
			for {
				select {
				case <-term:
					return nil
				case <-ctx.Done():
					return nil

				}
			}
		},
		func(error) {
			cancel()
		},
	)

	// Wait for the server to exit.
	g.Run()
}
