{{- define "head-deployment" -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "ray.head" . }}
  namespace: {{ .Values.clusterNamespace }}
  labels:
    component: ray-head
    type: ray
    ray-cluster-name: {{ .Values.clusterName }}
    appwrapper.mcad.ibm.com: {{ .Values.clusterName }}
spec:
  # Do not change this - Ray currently only supports one head node per cluster.
  replicas: 1
  selector:
    matchLabels:
      component: ray-head
      type: ray
  template:
    metadata:
      name: {{ include "ray.head" . }}
      namespace: {{ .Values.clusterNamespace }}
      labels:
        component: ray-head
        type: ray
        appwrapper.mcad.ibm.com: {{ .Values.clusterName }}
        app.kubernetes.io/name: {{ .Values.clusterName }}
        ray-node-type: head
        ray-cluster-name: {{ .Values.clusterName }}
        ray-user-node-type: rayHeadType
        ray-node-name: {{ include "ray.head" . }}

        {{ if eq .Values.mcad.scheduler "coscheduler" }}
        pod-group.scheduling.sigs.k8s.io: {{ include "ray.podgroup" . }}
        {{ end }}
    spec:
      {{- if .Values.rbac.enabled }}
      serviceAccountName: {{ include "ray.serviceaccount" . }}
      {{- end }}

      {{ if eq .Values.mcad.scheduler "coscheduler" }}
      schedulerName: scheduler-plugins-scheduler
      {{ end }}

      # If the head node goes down, the entire cluster (including all worker
      # nodes) will go down as well.
      restartPolicy: Always

      # This volume allocates shared memory for Ray to use for its plasma
      # object store. If you do not provide this, Ray will fall back to
      # /tmp which cause slowdowns if is not a shared memory volume.
      volumes:
      - name: dshm
        emptyDir:
          medium: Memory
      {{- if .Values.pvcs }}
      {{- if .Values.pvcs.claims }}
      {{- range $key, $val := .Values.pvcs.claims }}
      - name: {{ regexReplaceAll "\\." $val.name "-" }}
        persistentVolumeClaim:
          claimName: {{ regexReplaceAll "\\." $val.name "-" }}
      {{- end }}
      {{- end }}
      {{- end }}
      {{- if .Values.imagePullSecret }}
      imagePullSecrets:
        - name: {{ .Values.imagePullSecret }}
      {{- end }}
      containers:
        - name: ray-head
          image: {{ .Values.image }}
          imagePullPolicy: {{ .Values.imagePullPolicy }}
          command: [ "/bin/bash", "-c", "--" ]
          {{ if .Values.storage.secret }}
          envFrom:
            - secretRef:
                name: {{ .Values.storage.secret }}
          {{- end }}
          args:
            - {{ print "ray start --head --port=6379 --redis-shard-ports=6380,6381 --num-cpus=" .Values.podTypes.rayHeadType.CPUInteger " --num-gpus=" .Values.podTypes.rayHeadType.GPU " --object-manager-port=22345 --node-manager-port=22346 --dashboard-host=0.0.0.0 --storage=" .Values.storage.path " --block" }}
          ports:
            - containerPort: 6379 # Redis port
            - containerPort: 10001 # Used by Ray Client
            - containerPort: 8265 # Used by Ray Dashboard
            - containerPort: 8000 # Used by Ray Serve

          startupProbe:
            periodSeconds: {{ .Values.startupProbe.periodSeconds | default 10 }}
            failureThreshold: {{ .Values.startupProbe.failureThreshold | default 10 }}
            initialDelaySeconds: {{ .Values.startupProbe.initialDelaySeconds | default 5 }}
            httpGet:
              path: /
              port: 8265

          # make openshift local happy
          securityContext:
            runAsNonRoot: true
            allowPrivilegeEscalation: false

          # This volume allocates shared memory for Ray to use for its plasma
          # object store. If you do not provide this, Ray will fall back to
          # /tmp which cause slowdowns if is not a shared memory volume.
          volumeMounts:
            - mountPath: /dev/shm
              name: dshm
          {{- if .Values.pvcs }}
          {{- if .Values.pvcs.claims }}
          {{- range $key, $val := .Values.pvcs.claims }}
            - name: {{ regexReplaceAll "\\." $val.name "-" }}
              mountPath: {{ $val.mountPath }}
          {{- end }}
          {{- end }}
          {{- end }}
          resources:
            requests:
              cpu: {{ .Values.podTypes.rayHeadType.CPU }}
              memory: {{ .Values.podTypes.rayHeadType.memory }}
              ephemeral-storage: {{ .Values.podTypes.rayHeadType.storage }}
            limits:
              cpu: {{ .Values.podTypes.rayHeadType.CPU }}
              # The maximum memory that this pod is allowed to use. The
              # limit will be detected by ray and split to use 10% for
              # redis, 30% for the shared memory object store, and the
              # rest for application memory. If this limit is not set and
              # the object store size is not set manually, ray will
              # allocate a very large object store in each pod that may
              # cause problems for other pods.
              memory: {{ .Values.podTypes.rayHeadType.memory }}
              ephemeral-storage: {{ .Values.podTypes.rayHeadType.storage }}
              {{- if .Values.podTypes.rayHeadType.GPU }}
              nvidia.com/gpu: {{ .Values.podTypes.rayHeadType.GPU }}
              {{- end }}
{{- end }}
