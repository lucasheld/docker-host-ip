# docker-host-ip

This script creates a new docker bridge that uses a specified network interface for outgoging connections.

## Example

| Network interface | IP address    |
| :---------------- | :------------ |
| enp0s3            | 37.86.245.105 |
| enp0s8            | 83.149.89.20  |

| Docker bridge | used network interface |
| :------------ | :--------------------- |
| docker0       | enp0s3                 |
| **mybridge**  | **enp0s8**             |

The bold row is available after running:

```
$ ./run.sh
New docker bridge name: mybridge
Interface for outgoing connections: enp0s8
Interface DNS Server [1.1.1.1]:
Created new docker bridge "mybridge" with subnet "172.18.0.0/16"
Created new routing table entry
Created routes from bridge "mybridge" to interface "enp0s8"
IP address used by docker bridge "docker0": 37.86.245.105
IP address used by docker bridge "mybridge": 83.149.89.20
```
