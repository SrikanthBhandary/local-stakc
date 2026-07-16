output "admin_password" {
  value     = random_password.admin.result
  sensitive = true
}