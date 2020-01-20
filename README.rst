==============
jupyterhub-env
==============

---------------------------------
Setup dev instance of JupyterHub on Minikube
---------------------------------

1. Install kubectl. (https://kubernetes.io/docs/tasks/tools/install-kubectl/#install-kubectl-on-linux)

   I'm using Kubernetes version 1.14.0, therefore preferable to install 
   the same version of kubectl.

   On Linux:::

     # Download the specific version
     curl -LO https://storage.googleapis.com/kubernetes-release/release/v1.14.0/bin/linux/amd64/kubectl

     # Make the kubectl binary executable
     chmod +x ./kubectl

     # Move the binary in to your PATH
     sudo mv ./kubectl /usr/local/bin/kubectl

     # Test to ensure the version you installed is correct
     kubectl version --client

   Alternatively, using native package management, on Ubuntu:::

     sudo apt-get update && sudo apt-get install -y apt-transport-https
     curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
     echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list
     sudo apt-get update
     sudo apt-get install -y kubectl


2. Install a hypervisor such as VirtualBox

3. Install Minikube::

     curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 \
       && chmod +x minikube
     sudo mkdir -p /usr/local/bin/
     sudo install minikube /usr/local/bin/

4. Install a Kubernetes cluster::

     # So minikube doesn't try to automatically upgrade Kubernetes
     minikube config set kubernetes-version v1.14.0

     # Create a cluster using the profile `datahub`
     minikube start --profile datahub --memory=4096 --cpus=2 \
       --kubernetes-version=v1.14.0 \
       --vm-driver=virtualbox \
       --disk-size=30g \
       --extra-config=apiserver.enable-admission-plugins="LimitRanger,NamespaceExists,NamespaceLifecycle,ResourceQuota,ServiceAccount,DefaultStorageClass,MutatingAdmissionWebhook"

     # Set default profile as a convenience
     minikube profile datahub

     # So that Docker commands refer to the minikube instance
     eval $(minikube -p datahub docker-env)

5. Setup Helm::

     kubectl --namespace kube-system create serviceaccount tiller

     kubectl create clusterrolebinding tiller \
       --clusterrole cluster-admin \
       --serviceaccount=kube-system:tiller

     helm init --service-account tiller --wait

     # Ensure that tiller is secure from access inside the cluster.
     # Tiller's port is exposed in the cluster without authentication 
     # and if you probe this port directly (i.e. by bypassing helm) 
     # then tiller's permissions can be exploited. This step forces 
     # tiller to listen to commands from localhost (i.e. helm) only 
     # so that e.g. other pods inside the cluster cannot ask tiller 
     # to install a new chart granting them arbitrary, elevated RBAC 
     # privileges and exploit them.
     kubectl patch deployment tiller-deploy \
       --namespace=kube-system \
       --type=json \
       --patch='[{"op": "add", "path": "/spec/template/spec/containers/0/command", "value": ["/tiller", "--listen=localhost:44134"]}]'

   The latest version of Helm doesn't depend on tiller anymore; however,
   I'm using a proven combination.

6. Add PostgreSQL::

     RELEASE=postgres
     helm install --name $RELEASE stable/postgresql

7. Setup databases::

     # in another window, run the following (needed just to setup)
     kubectl port-forward --namespace default svc/postgres-postgresql 5432:5432 &

     POSTGRES_PASSWORD=$(kubectl get secret --namespace default postgres-postgresql -o jsonpath="{.data.postgresql-password}" | base64 --decode)

     # From the project root
     PGPASSWORD="$POSTGRES_PASSWORD" psql --host 127.0.0.1 -U postgres -d postgres -p 5432 -f ddl/create_databases.sql

8. Add custom Docker image for Jupyter Server container

   Install the image found at https://github.com/markmo/scipy-notebook::

     docker build -t "jupyter/scipy-notebook:latest" .

9. Update the JupyterHub config file

   Generate API keys using::

     openssl rand -hex 32

10. Add JupyterHub::

     helm repo add jupyterhub https://jupyterhub.github.io/helm-chart/
     helm repo update

     RELEASE=jhub
     NAMESPACE=jhub

     helm upgrade --install $RELEASE jupyterhub/jupyterhub \
       --namespace $NAMESPACE \
       --version=0.8.2 \
       --values config/config.yaml
