package main

import (
	"fmt"
	"os"

	"github.com/go-logr/logr"
	"gopkg.in/yaml.v3"
)

type Config struct {
	ResourceName        string `yaml:"resourceName"`
	NumberDevicesOnNode int    `yaml:"numberDevicesOnNode"`
	PluginName          string `yaml:"pluginName"`
	DeviceIDPrefix      string `yaml:"deviceIDPrefix"`
	AnnotationPrefix    string `yaml:"annotationPrefix,omitempty"`
	EnvPrefix           string `yaml:"envPrefix,omitempty"`
	DeviceFilePrefix    string `yaml:"deviceFilePrefix,omitempty"`
	deviceIDs           []string
}

func preparePluginConfiguration(path string, cfg *Config, logger logr.Logger) error {
	fd, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("could not open the configuration file: %v", err)
	}
	defer fd.Close()

	if err = yaml.NewDecoder(fd).Decode(cfg); err != nil {
		return fmt.Errorf("could not decode configuration file: %v", err)
	}

	setDeviceIDs(cfg)

	logger.Info("Plugin configuration:", "ResourceName", cfg.ResourceName,
		"NumberDevicesOnNode", cfg.NumberDevicesOnNode,
		"PluginName", cfg.PluginName,
		"DeviceIDPrefix", cfg.DeviceIDPrefix,
		"EnvPrefix", cfg.EnvPrefix,
		"DeviceFilePrefix", cfg.DeviceFilePrefix)

	return nil
}

func setDeviceIDs(config *Config) {
	nodeName := os.Getenv("NODE_NAME")
	config.deviceIDs = make([]string, config.NumberDevicesOnNode)
	for i := 0; i < config.NumberDevicesOnNode; i++ {
		config.deviceIDs[i] = fmt.Sprintf("%s-%s-%d", config.DeviceIDPrefix, nodeName, i)
	}
}
