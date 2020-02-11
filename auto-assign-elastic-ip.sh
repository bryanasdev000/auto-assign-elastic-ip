#!/usr/bin/env bash

# Fork de: https://github.com/heedsoftware/auto-assign-elastic-ip
# Licença: MIT License

# Método de implementação
# Chamada pelo userdata do script na imagem + cron para check de 5 em 5 minutos

# Comportamento
# Check se a maquina tem EIP se tiver encerrar por aqui
# Se nao tiver check por EIP disponiveis e tentar anexar a maquina

TIMEOUT=20
PAUSE=5
KEY=EIP

# Recon functions
aws_get_instance_id() {
	instance_id=$( (curl -s http://169.254.169.254/latest/meta-data/instance-id) )
	if [ -n "$instance_id" ];	then return 0; else return 1; fi
}

aws_get_instance_region() {
	instance_region=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
	# zona -> região
	instance_region=${instance_region::-1}
	if [ -n "$instance_region" ];	then return 0; else return 1; fi
}

aws_get_instance_environment() {
	instance_environment=$(aws ec2 describe-tags --region $instance_region --filters "Name=resource-id,Values=$1" "Name=key,Values=$KEY" --query "Tags[*].Value" --output text)
	echo $instance_environment
	if [ -n "$instance_environment" ]; then return 0; else return 1; fi
}

aws_get_existent_eip()
{
	check=$(aws ec2 describe-addresses --region $instance_region --filters "Name=instance-id,Values=$1" --query "Addresses[0].InstanceId" --output text)
  if [ "$instance_id" == "$check" ];	then return 0; else return 1; fi
}

aws_get_unassigned_eips() {
	local describe_addreses_response=$(aws ec2 describe-addresses --region $instance_region --filters "Name=tag:$KEY,Values=$instance_environment" --query "Addresses[?AssociationId==null].AllocationId" --output text)
	eips=(${describe_addreses_response///})
	if [ -n "$describe_addreses_response" ]; then return 0; else return 1; fi
}

aws_get_details() {
	if aws_get_instance_id;	then
		echo "Instance ID: ${instance_id}."
		if aws_get_instance_region;	then
			echo "Instance Region: ${instance_region}."
			if aws_get_instance_environment $instance_id;	then
				echo "Instance Environment: ${instance_environment}."
			else
				echo "Falha ao obter o Instance Environment. ${instance_environment}."
				echo "Máquina provavelmente não tageada."
				echo "Tag necessária: $EIP"
				echo "Precisa ter o mesmo valor no EIP e na instância (Worker)"
				return 1
			fi
		else
			echo "Falha ao obter o Instance Region. ${instance_region}."
			return 1
		fi
	else
		echo "Falha ao obter o Instance ID. ${instance_id}."
		return 1
	fi
}
# Recon functions

# EIP Magic
attempt_to_assign_eip() {
	echo 6
	local result;
	local exit_code;
  result=$( (aws ec2 associate-address --region $instance_region --instance-id $instance_id --allocation-id $1 --no-allow-reassociation) 2>&1 )
	exit_code=$?

	if [ $exit_code != '0' ] ; then
		echo "Falha ao atribuir o EIP [$1] para a instância [$instance_id]. ERRO: $result"
	fi
  return $exit_code
}

try_to_assign() {
	echo 7
	local last_result;
	for eip_id in "${eips[@]}"; do
		echo "Tentando atribuir um EIP para a instância..."
		if attempt_to_assign_eip $eip_id;  then
			echo "EIP atribuido com sucesso."
			return 0
		fi
	done
	return 1
}
# EIP Magic

# Main
main() {
	echo "EIP Assignment"

	local end_time=$((SECONDS+TIMEOUT))
	echo "Timeout de tentativas: ${end_time} segundos"

	if ! aws_get_details; then
		echo "Falha na obtenção da metadata da instância."
		exit 1
	fi

	echo "Check de EIP existente..."
	if aws_get_existent_eip ${region} ${instance_id}; then
		echo "instância possui EIP."
		exit 0

	else
		while [ $SECONDS -lt $end_time ]; do
			if aws_get_unassigned_eips && try_to_assign ${eips}; then
				echo "EIP associado com sucesso."
				exit 0
			fi
			echo "Falha em atribuir o EIP. Esperando por $PAUSE seguntos antes de tentar novamente..."
			sleep $PAUSE
		done
		echo "Falha em atribuir o EIP ao Worker depois de $TIMEOUT segundos. Saindo..."
		exit 1
	fi
}
# Main


# Caller
declare instance_id
declare instance_region
declare instance_environment
declare eips

main "$@"
# Caller
