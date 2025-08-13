function logar(){
    var login = document.getElementById('login').value;
    var password = document.getElementById('password').value;

    if(login == 'admin@teste.com' && password == 'admin@teste.com'){
        alert('Sucesso');
        location.href = 'home.html'
    } else{
        alert('Usuário ou senha incorretos');
    }
}