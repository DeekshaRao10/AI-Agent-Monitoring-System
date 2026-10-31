from anomaly_detector import detect_anomalies

print("\nTEST 1: Normal Activity")

normal = [5, 6, 7, 5, 8, 6, 7, 9]

print(detect_anomalies(normal))


print("\nTEST 2: Unusually Low Activity")

low = [10, 12, 11, 10, 13, 12, 11, 1]

print(detect_anomalies(low))


print("\nTEST 3: Inactivity")

inactive = [5, 6, 7, 8, 6, 7, 0]

print(detect_anomalies(inactive))