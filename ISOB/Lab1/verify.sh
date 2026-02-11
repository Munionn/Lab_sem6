set -e
echo "start"
echo ""

echo "1. Pinging host2 (192.168.100.11) from host1..."
docker exec host1 ping -c 2 192.168.100.11 && echo "   OK: host1 -> host2" || echo "   FAIL"

echo ""
echo "2. Pinging host3 (192.168.100.12) from host1..."
docker exec host1 ping -c 2 192.168.100.12 && echo "   OK: host1 -> host3" || echo "   FAIL"

echo ""
echo "3. Pinging host1 (192.168.100.10) from host2..."
docker exec host2 ping -c 2 192.168.100.10 && echo "   OK: host2 -> host1" || echo "   FAIL"

echo ""
echo "4. Checking interfaces on host1..."
docker exec host1 ip addr show eth0 | grep "inet "

echo ""
echo "end"
