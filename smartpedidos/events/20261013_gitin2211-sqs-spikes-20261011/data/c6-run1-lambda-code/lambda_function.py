import json
import boto3

def lambda_handler(event, context):
    ecs_client = boto3.client('ecs')
    cluster_name = 'smartfran-pedidos-production'
    service_name = 'platform-service-production-service'

    numero_tareas = 12
    limite_tareas = 15
    desired_tareas = 1
    #Sumar la diferencia de lo que falta para llegar a limite_tareas
    response = ecs_client.describe_services(
        cluster=cluster_name,
        services=[service_name]
    )
    print("Holas")
    tareas_actuales = response['services'][0]['runningCount']
    tareas_desired =  response['services'][0]['desiredCount']
    tareas_pending =  response['services'][0]['pendingCount']
    print(f"{response['services'][0].keys()}")
    
    print(f"Tareas Actuales: {tareas_actuales}")
    print(f"Limite de Tareas: {limite_tareas}")
    print(f"Tareas Deseadas antes: {tareas_desired}")
    print(f"Tareas Pendientes: {tareas_pending}")
    
    
    if tareas_actuales < limite_tareas:
        nuevo_numero_tareas = tareas_actuales + (limite_tareas - tareas_actuales)
        ecs_client.update_service(
            cluster=cluster_name,
            service=service_name,
            desiredCount=nuevo_numero_tareas
        )
        desired_after = response['services'][0]['desiredCount']
        return {
            'statusCode': 200,
            'body': f'Tareas Previas: {tareas_actuales}.\nTareas aumentadas a {nuevo_numero_tareas}.\nTareas Deseadas: {desired_after}'
        }
    else:
        return {
            'statusCode': 200,
            'body': f'No se aumentaron tareas. Tareas: {tareas_actuales}'
        }
