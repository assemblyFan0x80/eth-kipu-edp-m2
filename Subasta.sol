// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Auction {
    address public owner;
    address public highestBidder;
    uint public highestBid;
    uint public auctionEndTime;
    uint public commissionPercent = 2;
    bool public ended;

    struct Offer {
        uint amount;
        uint timestamp;
    }

    // Par de claves que guarda las oferas por cada direccion
    mapping(address => Offer[]) public offersByUser;

    // Guarda el registro de cuanta plata tiene que devolver el contrato
    mapping(address => uint) public refundableBalance;

    // Registra las direcciones de los oferentes
    address[] public bidders;

    // Eventos
    // nueva oferta
    event NewBid(address indexed bidder, uint amount);
    // fin de subasta
    event AuctionEnded(address winner, uint amount);

    // Funciones ejecutivas que solo puede hacer el dueño
    modifier onlyOwner() {
        require(msg.sender == owner, "Solo el owner puede hacer esto");
        _;
    }

    // Para que las funciones se ejecuten solo si estamos en tiempo de subasta
    modifier auctionActive() {
        require(block.timestamp < auctionEndTime, "La subasta ha finalizado");
        _;
    }

    // Las funciones que usen esto sabran que se termino la subasta
    modifier auctionEnded() {
        require(block.timestamp >= auctionEndTime || ended, "La subasta aun sigue");
        _;
    }
            
    // Para inicializar, solo necesitamos el tiempo de validez de la subasta en minutos
    constructor(uint _durationMinutes) {
        owner = msg.sender;
        auctionEndTime = block.timestamp + (_durationMinutes * 1 minutes);
    }


    // Atencion, aqui tenemos que decidir, si el dueño del articulo puede
    // ofertar o no. Si lo dejamos como está, si puede hacerlo.
    // Es decir, que el owner puede invocar la funcion bid. ¿Esta bien eso?
    // Funcion de subasta, payable, recibe Ethers mientras la subasta esta activa
    function bid() public payable auctionActive {
        require(msg.value > 0, "Debes ofertar un valor mayor a 0");
        require(msg.sender != highestBidder, "Ya eres el mejor postor");

        // La minima oferta valida superior en un 5% a la actual
        uint minRequired = highestBid + (highestBid * 5) / 100;
        
        // Si es la primera oferta, se acepta cualquier valor > 0
        if (highestBid == 0) {
            minRequired = 1; // Podemos poner un precio base? - ¿para diferenciarnos del resto?
        }

        require(msg.value >= minRequired, "Debes ofertar al menos 5% mas que la oferta actual");

        // Registra la oferta recibida por el usuario (la address en msg.sender)
        offersByUser[msg.sender].push(Offer({
            amount: msg.value,
            timestamp: block.timestamp
        }));

        // Registrar dirección en el array de oferentes si es la primera vez que participa
        if (offersByUser[msg.sender].length == 1) {
            bidders.push(msg.sender);
        }

        // (address(0) lo usamos para verificar que ya existe un mejor postor.
        // Si ya había un mejor postor anterior, se guarda su oferta anterior en refundableBalance, 
        // para que luego pueda retirarla (reembolso).
        // Esto evita que pierda el dinero que usó en su oferta anterior cuando alguien lo supera.
        if (highestBidder != address(0)) {
            refundableBalance[highestBidder] += highestBid;
            // Aqui guardamos la oferta anterior que fue superada para devolverla a la direccion
            // Esta direccion perdio la puja, entonces la guardamos para el reembolso al final
        }

        // Si tenemos un nuevo mejor postor, es quien genero la ultima oferta y su valor es
        // la nueva oferta mas alta
        highestBidder = msg.sender;
        highestBid = msg.value;

        // Extender la subasta si se hace una oferta en los últimos 10 minutos
        if (auctionEndTime - block.timestamp <= 10 minutes) {
            auctionEndTime += 10 minutes;
        }

        // Generar el evento "nueva oferta recibida"
        emit NewBid(msg.sender, msg.value);
    }

    // Obtener todas las ofertas, que hizo un usuario ( el array, desde una misma address)
    function getAllBids(address user) external view returns (Offer[] memory) {
        return offersByUser[user];
    }

    // Devuelve el array de oferentes
    function getAllBidders() external view returns (address[] memory) {
        return bidders;
    }

    function getWinner() external view auctionEnded returns (address, uint) {
        return (highestBidder, highestBid);
    }

    // Solo el dueño puede ejecutar esta funcion de terminar la subasta, si es que 
    // aun no ha finalizado
    function finalizeAuction() external onlyOwner auctionEnded {
        require(!ended, "Ya fue finalizada");
        ended = true;

        // determina la comision del 2% sobre la mejor oferta (que se la queda el contrato)
        uint commission = (highestBid * commissionPercent) / 100;
        // Precio final de la oferta ganadora
        uint sellerAmount = highestBid - commission;

        // Transferir el monto al dueño del articulo (el dueño del contrato)
        payable(owner).transfer(sellerAmount);

        // Generar el evento de finalizacion de la subasta
        emit AuctionEnded(highestBidder, highestBid);
    }

    // Una vez que la subasta ha terminado, checkeamos que quien resulto ganador
    // no pueda pedir el reembolso. Si se trata de otro usuario que hizo una oferta perdedora,
    // que fue guardada en el mapping de reembolsos por usuario. Si hay un importe guardado 
    // asociado a ese usuario, se le transfiere ese importe a su wallet.
    function refundLosingBids() external auctionEnded {
        require(msg.sender != highestBidder, "El ganador no puede pedir reembolso");
        uint amount = refundableBalance[msg.sender];
        require(amount > 0, "No tienes fondos para reembolso");

        // El usuario queda sin reembolsos pendientes
        refundableBalance[msg.sender] = 0;
        payable(msg.sender).transfer(amount);
    }

    // 🔁 Reembolso parcial DURANTE la subasta (antes de que termine)
    function partialWithdraw() external auctionActive {

        // Recuperamos todas las ofertas de un usuario. El uso de storage es necesario
        // para obtener una referencia directa al estado interno del contrato, para poder
        // modificar definitivamente (poner a 0) las transacciones en el array offersByUser
        // No nos sirve obtener una copia porque en ese caso, sucesivas llamadas a la funcion
        // seguirían determinando que hay ofertas por reembolsar. Con storage, hacemos esos
        // cambios (retiros) persistentes.
        Offer[] storage userOffers = offersByUser[msg.sender];
        // Siempre y cuando tenga alguna ...
        require(userOffers.length > 0, "No tienes ofertas registradas");

        uint total = 0;

        // Permitimos retirar todas las ofertas anteriores a la última oferta del usuario
        // El for es de cuidado, porque tenemos que cortar en (array.lenght -2) iterando
        // hasta el penultimo elemento. Si tengo 5 ofertas, lenght = 5, voy desde i = 0
        // hasta [ [array.lenght(5) - 1 (4)] - 1 (3)] es decir, esto sería
        // retirar las 4 ofertas userOffers[0],userOffers[1],userOffers[2] y userOffers[3]
        for (uint i = 0; i < userOffers.length - 1; i++) {
            total += userOffers[i].amount;
            userOffers[i].amount = 0; // marcar la oferta como retirada (en 0)
        }

        require(total > 0, "Nada que retirar");
        payable(msg.sender).transfer(total);
    }

    // Función auxiliar para obtener tiempo restante
    function timeLeft() external view returns (uint) {
        if (block.timestamp >= auctionEndTime) {
            return 0;
        }
        // Para mostrar el tiempo restante en minutos
        return (auctionEndTime - block.timestamp) / 60;
    }
}

