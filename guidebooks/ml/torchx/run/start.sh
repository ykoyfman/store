set -e
set -o pipefail

scheduler=${TORCHX_SCHEDULER-kubernetes_mcad}
component=${TORCHX_COMPONENT-dist.ddp}

# !!Workaround!! torchx's --num-cpus flag does not understand
# millicores, such as 250m. Below, look for the sed lines where we
# hack in the desired value.
NUM_CPUS_PLACEHOLDER=99999

# !!Workaround!! torchx does not handle Mi units
NUMERIC_PART=$(echo $WORKER_MEMORY | sed -E 's/[MGTP]i?//i')
SCALE_PART=$(echo $WORKER_MEMORY | sed -E 's/^.+Mi$/1/i' | sed -E 's/^.+Gi$/1024/i' | sed -E 's/^.+Ti$/1024 * 1024/i' | sed -E 's/^.+Pi$/1024 * 1024 * 1024/i')
WORKER_MEMORY_MB=$(($NUMERIC_PART * $SCALE_PART))

# TorchX Command Line Options
image="--image ${RAY_IMAGE}"
script="$(echo $CUSTOM_COMMAND_LINE_PREFIX | sed -E 's/^python[[:digit:]]+[ ]+//')"
if [ -n "$S3_S3FS_CLAIM" ] && [ -n "$S3_DATAPATH" ]; then
    volumes="--mounts type=volume,src=$S3_S3FS_CLAIM,dst=$S3_DATAPATH"
fi

# kubernetes_mcad scheduler Options
ns="namespace=${KUBE_NS}"
if [ -n "$IMAGE_PULL_SECRET" ]; then
    imagePullSecret=",image_secret=$IMAGE_PULL_SECRET"
fi
if [ "$KUBE_POD_SCHEDULER" = "coscheduler" ]; then
    coscheduler=",coscheduler_name=scheduler-plugins-scheduler"
fi
if [ -n "$RAY_IMAGE" ]; then
    repo=",image_repo=$(dirname $RAY_IMAGE)"
fi

cd $CUSTOM_WORKING_DIR && \
    torchx run --workspace="" \
           --dryrun \
           --scheduler $scheduler \
           --scheduler_args $ns$repo$imagePullSecret$coscheduler \
           $component \
           -j ${MAX_WORKERS}x1 --gpu ${NUM_GPUS} --cpu ${NUM_CPUS_PLACEHOLDER} --memMB ${WORKER_MEMORY_MB} \
           $volumes \
           $image \
           --script=$script \
        2>&1 \
        | awk '$0=="=== SCHEDULER REQUEST ===" {on=1} on==2 { print $0 } on==1{on=2}' \
        | sed "s/: $((NUM_CPUS_PLACEHOLDER * 1000))m/: ${NUM_CPUS}/g" \
        | sed "s/: $((NUM_CPUS_PLACEHOLDER * 1000 - 100))m/: ${NUM_CPUS}/g" \
        | sed "s/: ${NUM_CPUS_PLACEHOLDER}/: ${NUM_CPUS}/g" \
        | sed "s#$script#$script -- $GUIDEBOOK_DASHDASH#" \
        | sed "s/main-pg/pg/" \
        | sed -E "s/main-[a-zA-Z0-9]+/$TORCHX_INSTANCE/g" \
        | sed -E 's#(python -m torch.distributed.run|torchrun)#if [ -f /tmp/configmap/workdir/workdir.tar.bz2 ]; then export PYTHONPATH="${PYTHONPATH}:/tmp/workdir"; echo "Unpacking workspace with PYTHONPATH=$PYTHONPATH"; mkdir /tmp/workdir; tar -C /tmp/workdir -jxvf /tmp/configmap/workdir/workdir.tar.bz2; fi; cd /tmp/workdir; \1#' \
        | awk '{ idx=index($0, "volumeMounts:"); print $0; if (idx > 0) { for (i=1; i<idx; i++) printf " "; print "- name: workdir-volume"; for (i=1; i<idx+2; i++) printf " "; print "mountPath: /tmp/configmap/workdir"; for (i=1; i<idx+2; i++) printf " "; print "readOnly: true"} }' \
        | awk -v clusterName=$TORCHX_INSTANCE '{ idx=index($0, "volumes:"); print $0; if (idx > 0) { for (i=1; i<idx; i++) printf " "; print "- name: workdir-volume"; for (i=1; i<idx+2; i++) printf " "; print "configMap:"; for (i=1; i<idx+4; i++) printf " "; print "name: workdir-" clusterName} }' \
        > $HELM_ROLL_YOUR_OWN

echo "Torchx resources have been staged in $HELM_ROLL_YOUR_OWN"
