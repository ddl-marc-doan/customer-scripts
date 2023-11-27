#!/usr/bin/env python3

import boto3
import json
import argparse

parser = argparse.ArgumentParser()
parser.add_argument('--repo-pattern','-p',help='Name pattern for repos to check',required=True)
parser.add_argument('--verbose','-v',action='store_true')
parser.add_argument('--region','-r',default='us-east-1')

args = parser.parse_args()
name_pattern = args.repo_pattern
verbose = args.verbose
ecr = boto3.client('ecr',region_name=args.region)

repo_list_api = ecr.describe_repositories()['repositories']
repo_list = [repo for repo in repo_list_api if name_pattern in repo['repositoryName']]
if verbose:
    print(f'Repos matching "{name_pattern}": {[x["repositoryName"] for x in repo_list]}')

image_dict = {'ecrImageList':[]}
for repo in repo_list:
    img_list = ecr.describe_images(repositoryName=repo['repositoryName'])['imageDetails']
    img_sha_list = [{'imageDigest':img['imageDigest']} for img in img_list]
    if verbose:
        img_v = [img['imageDigest'] for img in img_list]
        print (f'Found the following image digests in {repo["repositoryName"]}: {img_v}')
    repo_dict = {'repositoryName':repo['repositoryName'],'imageIds':img_sha_list}
    image_dict['ecrImageList'].append(repo_dict)

print(json.dumps(image_dict))