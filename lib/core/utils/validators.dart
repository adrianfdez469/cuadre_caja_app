class Validators {
  // Validar campo no vacío
  static String? validateNotEmpty(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return 'Por favor ingrese $fieldName';
    }
    return null;
  }
  
  // Validar usuario
  static String? validateUsuario(String? value) {
    return validateNotEmpty(value, 'un usuario');
  }
  
  // Validar contraseña
  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Por favor ingrese una contraseña';
    }
    if (value.length < 3) {
      return 'La contraseña debe tener al menos 3 caracteres';
    }
    return null;
  }
  
  // Validar monto
  static String? validateAmount(String? value) {
    if (value == null || value.isEmpty) {
      return 'Por favor ingrese un monto';
    }
    
    final amount = double.tryParse(value);
    if (amount == null) {
      return 'Por favor ingrese un monto válido';
    }
    
    if (amount < 0) {
      return 'El monto no puede ser negativo';
    }
    
    return null;
  }
  
  // Validar cantidad de producto
  static String? validateQuantity(String? value) {
    if (value == null || value.isEmpty) {
      return 'Por favor ingrese una cantidad';
    }
    
    final quantity = double.tryParse(value);
    if (quantity == null) {
      return 'Por favor ingrese una cantidad válida';
    }
    
    if (quantity <= 0) {
      return 'La cantidad debe ser mayor a 0';
    }
    
    return null;
  }
}

