# simple-device-plugin
simple example of device plugin, using virtual( non-existent) device to demonstrate list and allocation of device

## initialization
the following is initialization sequence for device plugin:
1) create Grpc server
2) create an unix socket that Grpc server will listen on. it is customary
   to create it in the same directory as kubelet Grpc socket (/var/lib/kubelet/device-plugins).
   this socket will be used to receive requests from kubelet
3) register the struct the implements DevicePluginServer interface with your Grpc server
4) start Grpc server and register device plugin with kubelet. Registration is done via kubelet socket(/var/lib/kubelet/device-plugins/kubelet.sock)
   and contains the device plugin interface version, socket that the device plugin listens on, and the Resource name that the device-plugin provides
   (i.e example.com/simple-device). The resource name will appear on the nodes' extended resources and will be used in the Pods and resource to be used.
   Starting Grps server and registration must be done in parallel( goroutines), since the call to Grpc server start does not return.

## device plugin Grpc interface
kubelet communicates with device plugin using Grpc DevicePluginServer interface (https://github.com/kubernetes/kubelet/blob/4ee0161897c3790ca8fce67b96804a9fc508cecd/pkg/apis/deviceplugin/v1beta1/api.pb.go#L1357). There a number of functions, but usually only 3 need to be implemented:
- ListAndWatch
- Allocate
- GetDevicePluginOptions

### ListAndWatch
this function is called by kubelet to get the status of the devices on the node, their number, their IDs and their health. This data will be propagated
by kubelet to kkube API server, and will be stored in the extended resources of the node. It will also be used by kube scheduler to decide where to
schedule a pod, in case it will request the resource.
The IDs of the devices can be set to any value by the device-plugin, as long as it knows how to correlate them to the actual devices. Those IDs will 
be used by the kubelet to decide which device(s) should be allocated to each pod.


### Allocate
this function is called by the kubelet prior to scheduling pod on the node. The function's parameters will contain the IDs of all devices that kubelet
wants to allocated for the scheduled pod/container. The following action can be done by the device plugin on Allocate call:
1) verify the state/health of each requested device ( by IDs). In case the device is missing/unhealthy, the alllocate request can return an error
   in which case the pod/container will fail scheduling
2) add specific annotations to the response. Those annotation will be set by kubelet on the container using container runtime
3) add environment variable to the response. Those variable will be added to the container by the kubelet, using container runtime
4) define mounting of device on the container file-system. The needed volume/mount definitions will be added by kubelet to the container, 
   using container runtime. It means that Pod does not need to mount /dev host directory, the needed device files will be mounted by kubelet


## Simple Device Plugin deployment and configuration
Simple device plugin provides simple plugin implementation that can be configured as a simulator device plugin for various devices

### Configuration parameters
- `NAMESPACE`: the namespace where device should be deployed. Default value: `simple-device-plugin`
- `PLUGIN_NAME`: the name of the unix socket that will be defined for communicating with kubelet. In case more then one device-plugin
                 need to be deployed on the cluster, each device-plugin must have its own socket. Default value: `simple-device-plugin`
- `RESOURCE_NAME`: the resource name of the devices that will be reported to kubelet and then propogated to Kube API server and Scheduler.
                   Default value: `example.com/simple-device`
- `NUMBER_DEVICES`: number of simulated devices on the node, to be reported to the kubelet and Kube API. Default value: `2`
- `DEVICE_ID_PREFIX`: the prefix that will be used by the device-plugin to create device ids per simulate device per node.
                      the eventual device id reported to the kubelet will be: `<device-id-prefix>-<node-name>-<index-of-the-device>`
                      default value: `simple-device`
- `ANNOTATION_PREFIX`: the prefix that will be used to create an annotation on an allocated container.Default value is `""` (empty).
                       in case the value is empty, no annotation will be created on the container
- `ENV_PREFIX`: the prefix that will be used to create an environment variable on an allocated container.Default value is `""` (empty).
                in case the value is empty, no environment variable will be created. The value of the variable will be:
                `/dev/<index-of-the-device>`
- `DEVICE_FILE_PREFIX`: the prefix that will be used to map the device files of the host into the allocated container.
                        Default value is `""` (empty). in case the value is empty, no device will be mapped into the container.
                        In case prefix is defined, the host path for the mapped device will be `/dev/<device prefix>-<device-index>`,
                        and the container path will be the same.

### Makefile commands
Project is using skipper to run all the Makefile commands:
- `skipper make build`: build the executable
- `skipper make image`: create a container image for the device-plugin. It will also run the build stage if needed
- `skipper make deploy`: will deploy a device-plugin daemonset on the cluster, based on the kubeconfig provided via
                         KUBECONFIG variable. All the configuration parameters mentioned above can be passed to this command.
                         Example: `NAMESPACE=<some namespace> RESOURCE_NAME=<some resource name> skipper make deploy` will
                         deploy device plugin into namespace <some namespace> and it will report <some resource name> devices
                         to kubelet
- `skipper make undeploy`: will remove the deployment of the device plugin from the cluster. 
