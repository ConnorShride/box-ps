# Use an unroutable address to prevent leakage.
$r = [System.Net.WebRequest]::Create("http://0.0.0.0")
$r
