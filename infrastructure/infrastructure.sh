#!/bin/sh

az login
az account set

function parameters {
    export rg="VWAN001"
    export vwan_name="VWAN"

    export location0="centralus"
    export location1="eastus"

    export vhub0_name="vhub0-${location0}"
    export vhub1_name="vhub1-${location1}"
}

function report {
    az vm list-ip-addresses -g ${rg} --query "[].virtualMachine.{public_ip_address:network.publicIpAddresses[0].ipAddress, ip_address:network.privateIpAddresses[0], name:name}" -o table
}

function key_update {
    ips=`az vm list-ip-addresses -g ${rg} --query "[].virtualMachine.{public_ip_address:network.publicIpAddresses[0].ipAddress}" -o tsv`

    for ip in ${ips}; do 
        scp -o StrictHostKeyChecking=no ~/.ssh/id_rsa azureadmin@${ip}:~/.ssh
    done
}

function connectivity_check {

    echo "Verifying connectivity"

    ips=`az vm list-ip-addresses -g ${rg} --query "[].virtualMachine.{public_ip_address:network.publicIpAddresses[0].ipAddress, ip_address:network.privateIpAddresses[0], name:name}"`

    length=`echo $ips | jq 'length -1'`

    for s in `seq 0 $length`; do
        pip=`echo $ips | jq ".[${s}].public_ip_address" | tr -d '"'`
        name=`echo $ips | jq ".[${s}].name"| tr -d '"'`
        prip=`echo $ips | jq ".[${s}].ip_address"| tr -d '"'`

        echo "Pinging from $name ($pip:$prip)"
        for t in `seq 0 $length`; do
            if [ $s != $t ]; then
                tpip=`echo $ips | jq ".[${t}].public_ip_address" | tr -d '"'`
                tname=`echo $ips | jq ".[${t}].name"| tr -d '"'`
                tprip=`echo $ips | jq ".[${t}].ip_address"| tr -d '"'`

                echo "------> $tname ($tpip:$tprip)"
                ssh -o StrictHostKeyChecking=no azureadmin@$pip ping -c 4 $tprip 2>&1 | sed "s/^/        /g"
            fi
        done

    done
}

function my_ip() {
  ip=$(curl -s https://api.my-ip.io/ip)
  echo $ip
}

function iperf3_check {
    ips=`az vm list-ip-addresses -g ${rg} --query "[].virtualMachine.{public_ip_address:network.publicIpAddresses[0].ipAddress, ip_address:network.privateIpAddresses[0], name:name}"`

    length=`echo $a | jq 'length -1'`

    echo "prepping..."
    for s in `seq 0 $length`; do
        pip=`echo $ips | jq ".[${s}].public_ip_address" | tr -d '"'`
        ssh -o StrictHostKeyChecking=no azureadmin@$pip sudo apt-get install iperf3 -y 2>&1  > /dev/null
        ssh -o StrictHostKeyChecking=no azureadmin@$pip sudo apt-get install jq -y 2>&1  > /dev/null
        ssh -o StrictHostKeyChecking=no azureadmin@$pip iperf3 -s -D 2>&1  > /dev/null
    done

    for s in `seq 0 $length`; do
        pip=`echo $ips | jq ".[${s}].public_ip_address" | tr -d '"'`
        name=`echo $ips | jq ".[${s}].name"| tr -d '"'`
        prip=`echo $ips | jq ".[${s}].ip_address"| tr -d '"'`

        echo "iperf3 from $name ($pip:$prip)"
        for t in `seq 0 $length`; do
            if [ $s != $t ]; then
                tpip=`echo $ips | jq ".[${t}].public_ip_address" | tr -d '"'`
                tname=`echo $ips | jq ".[${t}].name"| tr -d '"'`
                tprip=`echo $ips | jq ".[${t}].ip_address"| tr -d '"'`

                echo "------> $tname ($tpip:$tprip)"
                ssh -o StrictHostKeyChecking=no azureadmin@$pip iperf3 -c ${tprip} -i0 -P64 -t 30 -J | jq ".end.sum_sent.bits_per_second,.end.sum_received.bits_per_second" 2>&1 | sed "s/^/        /g"
            fi
        done

    done
}

function vmss_show {
   az vmss list -g ${rg} -o table


}

function infra_create {
    
    echo "Creating VWAN and VHUB"

    az network vwan create --name ${vwan_name} --resource-group ${rg} --type Standard --location ${location0}

    az network vhub create --address-prefix 10.100.0.0/24 \
                            --name ${vhub0_name} \
                            --resource-group ${rg} \
                            --vwan ${vwan_name}  \
                            --location ${location0}

    az network vhub create --address-prefix 10.101.0.0/24 \
                            --name ${vhub1_name} \
                            --resource-group ${rg} \
                            --vwan ${vwan_name} \
                            --location ${location1}  

    echo "Creating NSGs"

    for location in $location0 $location1; do
        az network nsg create --name $location \
                            --resource-group $rg \
                            --location $location

        az network nsg rule create --name SSH \
                                --nsg-name $location \
                                --priority 100 \
                                --resource-group $rg \
                                --access Allow \
                                --destination-address-prefixes 0.0.0.0/0 \
                                --destination-port-ranges "*" \
                                --direction Inbound \
                                --protocol "*" \
                                --source-address-prefixes "$(my_ip)/32" 

        az network nsg rule create --name TEN \
                                --nsg-name $location \
                                --priority 200 \
                                --resource-group $rg \
                                --access Allow \
                                --destination-address-prefixes 0.0.0.0/0 \
                                --destination-port-ranges "*" \
                                --direction Inbound \
                                --protocol "*" \
                                --source-address-prefixes "10.0.0.0/8"
    done

                        
    echo "Creating Workload VNETs"

    # Location 0                        
    az network vnet create --name "${location0}-0" \
                            --resource-group ${rg} \
                            --address-prefixes 10.0.0.0/16 \
                            --subnet-name default \
                            --subnet-prefixes 10.0.1.0/24 \
                            --location ${location0} \
                            --network-security-group ${location0}

    az network vnet create --name "${location0}-1" \
                            --resource-group ${rg} \
                            --address-prefixes 10.1.0.0/16 \
                            --subnet-name default \
                            --subnet-prefixes 10.1.1.0/24 \
                            --location ${location0} \
                            --network-security-group ${location0}

    # Location 1

    az network vnet create --name "${location1}-0" \
                            --resource-group ${rg} \
                            --address-prefixes 10.2.0.0/16 \
                            --subnet-name default \
                            --subnet-prefixes 10.2.1.0/24 \
                            --location ${location1} \
                            --network-security-group ${location1}

    az network vnet create --name "${location1}-1" \
                            --resource-group ${rg} \
                            --address-prefixes 10.3.0.0/16 \
                            --subnet-name default \
                            --subnet-prefixes 10.3.1.0/24 \
                            --location ${location1} \
                            --network-security-group ${location1}

    echo "Creating full mesh"

    locations=($location0 $location1)
    locations_last=`expr ${#locations[@]} - 1`

    for s in `seq 0 $locations_last`; do \

        vhub_name="vhub${s}-${locations[$s]}"
        location=${locations[$s]}

        for id in 0 1; do \

            vnet="${location}-${id}"
            
            az network vhub connection create --name ${vnet} \
                                                --remote-vnet "${vnet}" \
                                                --resource-group ${rg} \
                                                --vhub-name ${vhub_name} 
        done
    done

}

function vm_create {
    echo "Create VM for testing"

    for location in ${location0} ${location1} ; do \
        for id in 0 1; do \

            vnet="${location}-${id}"

            az vm create --resource-group ${rg} \
                                    --name "${location}-${id}" \
                                    --image UbuntuLTS \
                                    --vnet-name $vnet \
                                    --subnet default \
                                    --admin-username azureadmin \
                                    --public-ip-sku Standard \
                                    --ssh-key-values @~/.ssh/id_rsa.pub \
                                    --nsg-rule SSH \
                                    --location $location \
                                    --accelerated-networking true \
                                    --size "Standard_D2_V5" # "Standard_DS4_v2" #"Standard_D2_v5" # "Standard_D4_v5" #12500 https://docs.microsoft.com/en-us/azure/virtual-machines/dv5-dsv5-series 
        done
    done

}

function firewall_create {
    echo "Adding Firewall Policy"

    az deployment group create --resource-group ${rg} --template-file firewall_policy/template.json --parameters location=${location0} --parameters firewallPolicyName=AZFWPP --parameters resourceGroup=${rg}

    az network firewall create --name AZFWP \
                            --resource-group ${rg} \
                            --firewall-policy AZFWPP \
                            --location $location0 \
                            --sku AZFW_Hub \
                            --tier Premium \
                            --vhub $vhub0_name \
                            --public-ip-count 1




}

function vmss1_create {
    echo "Creating VMSS 1 in ${location0} "

    id=1

    # az network public-ip create --name LBFE0 \
    #                 --resource-group ${rg} \
    #                 --allocation-method Static \
    #                 --location ${location0} \
    #                 --sku Standard

    # az network lb create --name pub-${location0}-${id} \
    #                     --resource-group ${rg} \
    #                     --backend-pool-name ${location0}-${id} \
    #                     --frontend-ip-name LBFE0 \
    #                     --location ${location0} \
    #                     --public-ip-address LBFE0 \
    #                     --public-ip-address-allocation Static \
    #                     --sku Standard 

    az vmss create --name ${location0}-${id}  \
                    --resource-group $rg \
                    --accelerated-networking true \
                    --admin-username azureadmin \
                    --authentication-type ssh \
                    --custom-data ./server_config.sh \
                    --image UbuntuLTS \
                    --instance-count 0 \
                    --location $location0 \
                    --ssh-key-values  @~/.ssh/id_rsa.pub \
                    --subnet default \
                    --vm-sku "Standard_D2_V5" \
                    --public-ip-address "" \
                    --lb "" \
                    --vnet-name ${location0}-${id} #\
                    # --lb "${location0}-${id}" \
                    # --lb-sku Standard \
                    # --backend-pool-name "${location0}-${id}"

    #backend_id=`az network lb address-pool show --lb-name pub-${location0}-${id} --name ${location0}-${id} -g ${rg} --query "id" -o tsv`

    # az vmss update --name ${location0}-${id} \
    #                 --resource-group $rg \
    #                 --add virtualMachineProfile.networkProfile.networkInterfaceConfigurations[0].ipConfigurations[0].loadBalancerBackendAddressPools \
    #                 "id=${backend_id}"

    # az network lb probe create --lb-name ${location0}-${id} \
    #                         --name tcp80 \
    #                         --port 80 \
    #                         --protocol Tcp \
    #                         --resource-group $rg

    # az network lb rule create --backend-port 5201 \
    #                         --frontend-port 5201 \
    #                         --lb-name ${location0}-${id} \
    #                         --name iperf3 \
    #                         --protocol Tcp \
    #                         --resource-group $rg \
    #                         --backend-pool-name ${location0}-${id} \
    #                         --load-distribution None \
    #                         --probe-name tcp80 \
    #                         --frontend-ip-name loadBalancerFrontEnd

    # az network public-ip prefix create --length 28 --location ${location0} --name PLBFE --resource-group ${rg}
                
    # az network lb frontend-ip create --lb-name pub-${location0}-${id} \
    #                                 --name LBFE \
    #                                 --resource-group $rg \
    #                                 --public-ip-prefix PLBFE 

    # az network lb outbound-rule create --address-pool ${location0}-${id} \
    #                                --frontend-ip-configs LBFE \
    #                                --lb-name pub-${location0}-${id} \
    #                                --name pub-out \
    #                                --protocol All \
    #                                --resource-group ${rg} 

}

function vmss0_create {
    echo "Creating VMSS 0 in ${location0}"

    #id=1

    #$target=`az network lb show --name ${location0}-${id} --resource-group ${rg} --query "frontendIpConfigurations[].privateIpAddress" -o tsv`

    #cat client.sh | sed -e s/TARGET/$target/ > client_config.sh 

    id=0

    az vmss create --name ${location0}-${id}  \
                    --resource-group $rg \
                    --accelerated-networking true \
                    --admin-username azureadmin \
                    --authentication-type ssh \
                    --custom-data ./client_config.sh \
                    --image UbuntuLTS \
                    --instance-count 0 \
                    --location $location0 \
                    --ssh-key-values  @~/.ssh/id_rsa.pub \
                    --subnet default \
                    --vm-sku "Standard_D2_V5" \
                    --public-ip-address "" \
                    --lb "" \
                    --vnet-name ${location0}-${id} 
 
}

function vmss_scale {
        
    capacity=$1

    az vmss scale --new-capacity ${capacity} \
                    --name ${location0}-0 \
                    --resource-group ${rg} \
                    --no-wait

    az vmss scale --new-capacity ${capacity} \
                    --name ${location0}-1 \
                    --resource-group ${rg} \
                    --no-wait
}

function rt_create {

    az network route-table create --name RT --resource-group ${rg}

    az network route-table route create --address-prefix "`my_ip`/32" --name "backdoor" --next-hop-type Internet --resource-group ${rg} --route-table-name RT

    for location in ${location0} ; do \
        for id in 0 1; do \

            vnet="${location}-${id}"

            az network vnet subnet update --name default \
                                    --resource-group ${rg} \
                                    --route-table RT \
                                    --vnet-name ${vnet}
        done
    done
}

function storage_create {

    az storage account create -n storageiperf3 -g ${rg} -l ${location0} --sku Standard_LRS

    key=`az storage account keys list --account-name storageiperf3 --query "[0].value" -o tsv`

    export CONNECTION_STRING=`az storage account show-connection-string --key primary --name storageiperf3 -o tsv`

    az storage queue create --name qiperf3 \
                            --account-key "${key}" \
                            --account-name storageiperf3 \
                            --auth-mode key 
    
    envsubst < server.sh  > server_config.sh 
    envsubst < client.sh  > client_config.sh
}

az group create --name ${rg} --location ${location0}
# az account list-locations -o table

infra_create

vm_create

key_update

connectivity_check

firewall_create

# https://docs.microsoft.com/en-us/azure/firewall/firewall-preview
Connect-AzAccount
Select-AzSubscription -SubscriptionName 
Register-AzProviderFeature -FeatureName AFWEnableAccelnet -ProviderNamespace Microsoft.Network
Register-AzResourceProvider -ProviderNamespace Microsoft.Network


echo "At this point you should manually enable securing traffic spoke to spoke"
echo "Azure Firewall Policy -> vhub -> Security Configuration"

storage_create

vmss1_create
vmss0_create

vmss_scale 20


