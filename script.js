function logar(){
    var login = document.getElementById('login').value;
    var password = document.getElementById('password').value;

    if(login == 'timeitj@selbetti.com.br' && password == 'recruta7070'){
        alert('Sucesso');
        location.href = 'home.html'
    } else{
        alert('Usuário ou senha incorretos');
    }
}

function copiarComando(botao) {
    const comando = botao.getAttribute("data-comando");
    navigator.clipboard.writeText(comando).then(() => {
        alert("Comando copiado: " + comando);
    }).catch(err => {
        alert("Erro ao copiar: " + err);
    });
}