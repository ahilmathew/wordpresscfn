#!/usr/bin/env bash
#set -x
usage="Usage: $(basename "$0") region stack-name template [aws-cli-opts]
where:
  region       - the AWS region
  stack-name   - the stack name
  template     - the cloudformation template to deploy
  aws-cli-opts - extra options passed directly to create-stack/update-stack
"

if [ "$1" == "-h" ] || [ "$1" == "--help" ] || [ "$1" == "help" ] || [ "$1" == "usage" ] ; then
  echo "$usage"
  exit -1
fi

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] ; then
  echo "$usage"
  exit -1
fi

stack_name=$2

aws_region=$1

type=""
wait_type=""

echo "Getting stack $stack_name details.."
aws cloudformation describe-stacks --region $aws_region --stack-name $stack_name > /dev/null
status=$?
if [ $status -ne 0 ] ; then
    type='create-stack'
    wait_type='stack-create-complete'
    echo "Going to $type $stack_name"
else
    type='update-stack'
    wait_type='stack-update-complete'
    echo "Going to $type $stack_name"
fi

#Default Parameters
default_instance_type=t2.small
default_dbinstance_type=db.t2.small
db_name="${stack_name}db"
multi_az=false
db_Size=5
min_ASG=2
max_ASG=5
desired_ASG=2
declare -A parameters

echo "Enter EC2 Instance Type, or press [ENTER] (defaults to $default_instance_type):"
read instanceType
parameters["InstanceType"]=${instanceType:=$default_instance_type}

echo "Enter RDS DB Instance Type, or press [ENTER] (defaults to $default_dbinstance_type):"
read dbInstanceType
parameters["DBClass"]=${dbInstanceType:=$default_dbinstance_type}

echo "Enter RDS DB Name, or press [ENTER]: (defaults to $db_name)"
read dbName
parameters["DBName"]=${dbName:=$db_name}

echo "Enter RDS DB UserName, followed by [ENTER]:"
read dbUser
parameters["DBUser"]=$dbUser

echo "Enter RDS DB Password, followed by [ENTER]:"
read -s dbPassword
parameters["DBPassword"]=$dbPassword

echo "Do you want to deploy a Multi AZ RDS Database, [true or false] (defaults to $multi_az):"
read multiAZ
parameters["MultiAZDatabase"]=${multiAZ:=$multi_az}

echo "Enter Database size (Gb), or press [ENTER] (defaults to $db_Size GB):"
read dbSize
parameters["DBAllocatedStorage"]=${dbSize:=$db_Size}

echo "Enter minimum number of instances to be deployed, or press [ENTER] (defaults to $min_ASG):"
read minASG
parameters["MinimumASGSize"]=${minASG:=$min_ASG}

echo "Enter maximum number of instances that can be deployed, or press [ENTER] (defaults to $max_ASG):"
read maxASG
parameters["MaximumASGSize"]=${maxASG:=$max_ASG}

echo "Enter current desired number of instances to be deployed, or press [ENTER] (defaults to $desired_ASG):"
read desiredCapacity
parameters["WebServerCapacity"]=${desiredCapacity:=$desired_ASG}

template_file=$3

s_parameters=''
for i in "${!parameters[@]}" ; do
    s_parameters=$s_parameters' '$(printf "ParameterKey=%s,ParameterValue=%s" $i ${parameters[${i}]})
done

eval "aws --region $aws_region cloudformation $type --stack-name $stack_name --template-body 'file://$template_file' --parameters $s_parameters"

status=$?

if [ $status -ne 0 ] ; then
    # Don't fail for no-op update
    if [[ $update_output == *"ValidationError"* && $update_output == *"No updates"* ]] ; then
        echo -e "\nFinished create/update - no updates to be performed"
        exit 0
    else
        exit $status
    fi

fi

echo "Waiting for stack update to complete ..."
  aws cloudformation wait $wait_type \
    --region $aws_region \
    --stack-name $stack_name
website_url=`aws cloudformation describe-stacks --stack-name $stack_name --query "Stacks[0].Outputs[?OutputKey=='WebsiteURL'].OutputValue" --output text`
#exec aws --region $api_region cloudformation describe-stacks --stack-name $api_stack_name
echo "Finished create/update successfully!"
echo "Website URL: $website_url"