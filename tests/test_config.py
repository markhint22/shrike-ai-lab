"""
Test Configuration Files
========================
Validates configuration files are properly formatted.
"""

import pytest
import yaml
from pathlib import Path

CONFIG_DIR = Path(__file__).parent.parent / "configs"


class TestLiteLLMConfig:
    """Test LiteLLM configuration."""
    
    def test_config_exists(self):
        """Verify litellm_config.yaml exists."""
        config_file = CONFIG_DIR / "litellm_config.yaml"
        assert config_file.exists(), f"Missing {config_file}"
    
    def test_config_valid_yaml(self):
        """Verify config is valid YAML."""
        config_file = CONFIG_DIR / "litellm_config.yaml"
        with open(config_file) as f:
            config = yaml.safe_load(f)
        assert config is not None, "Config file is empty"
    
    def test_config_has_model_list(self):
        """Verify config has model_list."""
        config_file = CONFIG_DIR / "litellm_config.yaml"
        with open(config_file) as f:
            config = yaml.safe_load(f)
        
        assert "model_list" in config, "Missing model_list in config"
        assert len(config["model_list"]) > 0, "model_list is empty"
    
    def test_specpilot_model_configured(self):
        """Verify specpilot-local model is configured."""
        config_file = CONFIG_DIR / "litellm_config.yaml"
        with open(config_file) as f:
            config = yaml.safe_load(f)
        
        model_names = [m.get("model_name") for m in config.get("model_list", [])]
        assert "specpilot-local" in model_names, "specpilot-local model not configured"
        print(f"✅ Configured models: {model_names}")
    
    def test_local_models_use_ollama(self):
        """Verify local models route to Ollama."""
        config_file = CONFIG_DIR / "litellm_config.yaml"
        with open(config_file) as f:
            config = yaml.safe_load(f)
        
        local_models = [m for m in config.get("model_list", []) 
                       if "local" in m.get("model_name", "")]
        
        for model in local_models:
            params = model.get("litellm_params", {})
            model_id = params.get("model", "")
            assert model_id.startswith("ollama/"), \
                f"Local model {model.get('model_name')} should use ollama/ prefix"
    
    def test_fallback_model_configured(self):
        """Verify cloud fallback is configured."""
        config_file = CONFIG_DIR / "litellm_config.yaml"
        with open(config_file) as f:
            config = yaml.safe_load(f)
        
        model_names = [m.get("model_name") for m in config.get("model_list", [])]
        has_fallback = any("fallback" in name or "claude" in name for name in model_names)
        assert has_fallback, "No cloud fallback model configured"


class TestDockerComposeConfig:
    """Test Docker Compose configuration."""
    
    def test_docker_compose_exists(self):
        """Verify docker-compose.yml exists."""
        compose_file = Path(__file__).parent.parent / "docker-compose.yml"
        assert compose_file.exists()
    
    def test_docker_compose_valid_yaml(self):
        """Verify docker-compose.yml is valid YAML."""
        compose_file = Path(__file__).parent.parent / "docker-compose.yml"
        with open(compose_file) as f:
            config = yaml.safe_load(f)
        assert config is not None
    
    def test_required_services_defined(self):
        """Verify required services are defined."""
        compose_file = Path(__file__).parent.parent / "docker-compose.yml"
        with open(compose_file) as f:
            config = yaml.safe_load(f)
        
        services = config.get("services", {})
        required = ["ollama", "litellm"]
        
        for service in required:
            assert service in services, f"Missing required service: {service}"
        
        print(f"✅ Services defined: {list(services.keys())}")
    
    def test_ollama_has_gpu_config(self):
        """Verify Ollama service has GPU configuration."""
        compose_file = Path(__file__).parent.parent / "docker-compose.yml"
        with open(compose_file) as f:
            config = yaml.safe_load(f)
        
        ollama = config.get("services", {}).get("ollama", {})
        deploy = ollama.get("deploy", {})
        resources = deploy.get("resources", {})
        reservations = resources.get("reservations", {})
        devices = reservations.get("devices", [])
        
        has_gpu = any(d.get("capabilities") == ["gpu"] for d in devices)
        assert has_gpu, "Ollama service should have GPU configuration"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
