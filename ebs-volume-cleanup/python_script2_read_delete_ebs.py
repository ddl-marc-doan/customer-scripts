#! /usr/bin/env python3
import os,sys,argparse,boto3,jmespath,time,datetime,json
from datetime import datetime

parser = argparse.ArgumentParser()
parser.add_argument('--dry-run',action='store_true')
parser.add_argument('--cluster-name','-c',required=True)
parser.add_argument('--namespace','-n', default='domino-compute')
parser.add_argument('--tags','-t',help='Additional tags to check, format: "key1=value1,key2=value2"')
parser.add_argument('--pvc-file','-f',default='pvc_names_output.txt')
parser.add_argument('--remove-before-date','-r',default='2023-06-01',help='Remove volumes created before date')
parser.add_argument('--check-cloudtrail',action='store_true')
parser.add_argument('--verbose','-v',action='store_true')
parser.add_argument('--region',default='us-east-1')

args = parser.parse_args()
cluster = args.cluster_name
ns = args.namespace
pvc_file = args.pvc_file
addl_tags = []
volume_older_than_date = datetime.astimezone(datetime.strptime(args.remove_before_date,'%Y-%m-%d'))

if args.tags:
    tag_list = args.tags.split(',')
    addl_tags = [{'Name':f'tag:{tag.split("=")[0]}','Values':[tag.split('=')[1]]} for tag in tag_list]

ec2 = boto3.client('ec2',region_name=args.region)
if args.check_cloudtrail:
    cloudtrail = boto3.client('cloudtrail',region_name=args.region)

if not os.path.isfile(pvc_file):
    print(f'Could not find file {pvc_file}. Check that it exists at the path provided and that you have permissions to read it.')
    sys.exit(1)

with open(pvc_file) as f:
    source_pvc_list = [line.rstrip() for line in f.readlines()]

def print_vol_list(vols:[]):
    for vol in vols:
        #  print(vol)
        vol_name = jmespath.search("Tags[?Key=='Name'].Value",vol)[0]
        print(f'Name: {vol_name}, VolumeID: {vol["VolumeId"]}, Size: {vol["Size"]}GB, Creation Date: {vol["CreateTime"].isoformat()}')

# Get the list of volumes matching the cluster, namespace, and any additional tags that we want to provide.
paginator = ec2.get_paginator('describe_volumes')
paginator_params = [
        {'Name':'status','Values':['available']},
        {'Name':f'tag:kubernetes.io/cluster/{cluster}','Values':['owned']},
        {'Name':'tag:kubernetes.io/created-for/pvc/namespace','Values':[ns]},
    ] + addl_tags
ebs_list = [page['Volumes'] for page in paginator.paginate(Filters=paginator_params)][0]

if args.verbose:
    pvc_list_print = []
    for vol in ebs_list:
        pvc = jmespath.search("Tags[?Key=='kubernetes.io/created-for/pvc/name'].Value",vol)[0]
        if pvc in source_pvc_list:
            pvc_list_print.append(vol)
    ebs_list_print = [vol for vol in ebs_list if vol['CreateTime'] < volume_older_than_date]
    print(f'Found the following base volumes for cluster {cluster}, older than {volume_older_than_date}:')
    print('============================')
    print_vol_list(ebs_list_print)
    print('============================')
    print('PVC-associated volumes from original list:')
    print_vol_list(pvc_list_print)
    print('============================')

ebs_list = [vol for vol in ebs_list if vol['CreateTime'] < volume_older_than_date]
for vol in ebs_list:
    pvc = jmespath.search("Tags[?Key=='kubernetes.io/created-for/pvc/name'].Value",vol)[0]
    if pvc in source_pvc_list:
        ebs_list.remove(vol)

if args.check_cloudtrail:
    if args.verbose:
        print('Checking for any volume attach/detach activity in CloudTrail...')
    for vol in ebs_list:
        now = datetime.now()
        ct_events = cloudtrail.lookup_events(
            LookupAttributes = [
                {'AttributeKey': 'ResourceName','AttributeValue': vol}
            ],
            StartTime=datetime(2015,1,1),
            EndTime=now
        )['Events']
        ct_events = [event for event in ct_events if event['EventName'] == 'AttachVolume' or event['EventName'] == 'DetachVolume' ]
        if len(ct_events) > 0:
            if args.verbose:
                print(f"Found event data for volume {vol}:")
            for event in ct_events:
                if args.verbose:
                    print(f"Event: Volume ID {vol}, Action: {event['EventName']}, Date: {datetime.strftime(event['EventTime'],'%Y-%m-%d %H:%M:%S')} ")
                    print(f"Removing volume {vol} from safe-to-delete list...")
                ebs_list.remove(vol)

print("Volumes not associated with any PVC (safe to delete):")
print_vol_list(ebs_list)

if not args.dry_run:
    print("Script was run with --dry-run=False")
    print("The following volumes will be deleted:\n")
    print_vol_list(ebs_list)
    are_you_sure = input("Are you sure you want to delete these volumes? (yes/no) ")
    if are_you_sure != "yes":
        print("Exiting...")
        sys.exit(0)
    else:
        print("Proceeding to delete volumes in 10 seconds: if you're not sure, Ctrl+C now!")
        time.sleep(10)
        for vol in ebs_list:
            vol_id_to_delete = vol['VolumeId']
            resp = ec2.delete_volume(vol_id_to_delete)
            print(json.dumps(resp))