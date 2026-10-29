# ============================================================================
# JOGA BONITO — imagem da API .NET 8 + front-end estático
# Build a partir da pasta Site/:  docker build -f backend/Dockerfile -t jogabonito-api .
# ============================================================================

# ---------- Etapa 1: build e testes ----------
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY backend/JogaBonito.Api.csproj backend/
COPY tests/JogaBonito.Tests/JogaBonito.Tests.csproj tests/JogaBonito.Tests/
RUN dotnet restore tests/JogaBonito.Tests/JogaBonito.Tests.csproj
COPY backend/ backend/
COPY tests/ tests/
RUN dotnet test tests/JogaBonito.Tests/JogaBonito.Tests.csproj --no-restore -c Release \
 && dotnet publish backend/JogaBonito.Api.csproj --no-restore -c Release -o /out

# ---------- Etapa 2: runtime enxuto ----------
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS final
WORKDIR /app/backend
COPY --from=build /out .
# Front-end e scripts SQL ficam em /app (a API procura em ../)
COPY HTML/ /app/HTML/
COPY CSS/ /app/CSS/
COPY Javascript/ /app/Javascript/
COPY IMG/ /app/IMG/
COPY banco/ /app/banco/

ENV Urls=http://+:5000 \
    Site__Raiz=/app \
    ASPNETCORE_ENVIRONMENT=Production
EXPOSE 5000

# Executa sem privilégios de root
USER app
# Monitoramento: GET /health/live (processo) e GET /health/ready (API + SQL Server)
ENTRYPOINT ["dotnet", "JogaBonito.Api.dll"]
