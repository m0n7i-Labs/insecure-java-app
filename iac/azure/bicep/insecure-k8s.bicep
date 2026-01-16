// insecure-deployment.bicep
param location string = resourceGroup().location
param prefix string = 'lab'
param uniqueSuffix string = uniqueString(resourceGroup().id)

var clusterName = '${prefix}-aks-${uniqueSuffix}'
var synapseWsName = '${prefix}-synapse-${uniqueSuffix}'
var storageName = 'st${uniqueSuffix}'

// --- PREREQUISITE: STORAGE FOR SYNAPSE ---
resource storage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageName
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: { isHnsEnabled: true } // Required for Synapse
}

// --- TARGET 1: INSECURE AKS CLUSTER ---
// Triggers: AKS-024, AKS-023, AKS-013, AKS-016, AKS-022, AKS-002
resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-03-01' = {
  name: clusterName
  location: location
  identity: { type: 'SystemAssigned' }
  properties: {
    dnsPrefix: clusterName
    agentPoolProfiles: [
      {
        name: 'agentpool'
        count: 1
        vmSize: 'Standard_DS2_v2'
        mode: 'System'
        // Trigger AKS-024: Missing diskEncryptionSetID
      }
    ]
    // Trigger AKS-016: Local accounts enabled (not disabled)
    disableLocalAccounts: false 
    
    // Trigger AKS-002: Azure RBAC disabled
    enableRBAC: false 

    networkProfile: {
      networkPlugin: 'azure'
      // Trigger AKS-023: No Network Policy (calico/azure)
      networkPolicy: 'none' 
    }

    apiServerAccessProfile: {
      // Trigger AKS-022: Authorized IP ranges are empty/unset
      authorizedIPRanges: [] 
    }

    // Trigger AKS-013: Container Insights (omsagent) disabled
    addonProfiles: {
      omsagent: {
        enabled: false
      }
    }
  }
}

// --- TARGET 2: SYNAPSE WORKSPACE & POOL ---
resource synapseWorkspace 'Microsoft.Synapse/workspaces@2021-06-01' = {
  name: synapseWsName
  location: location
  identity: { type: 'SystemAssigned' }
  properties: {
    defaultDataLakeStorage: {
      accountUrl: 'https://${storageName}.dfs.core.windows.net'
      filesystem: 'users'
    }
  }
}

// Trigger DatabaseServer-063: Isolated compute disabled
resource sparkPool 'Microsoft.Synapse/workspaces/bigDataPools@2021-06-01' = {
  parent: synapseWorkspace
  name: 'insecurepool'
  location: location
  properties: {
    nodeSizeFamily: 'MemoryOptimized'
    nodeSize: 'Medium' // Must be XXXLarge for isolation
    isComputeIsolationEnabled: false // The specific trigger
    autoScale: {
      enabled: true
      minNodeCount: 3
      maxNodeCount: 5
    }
  }
}
