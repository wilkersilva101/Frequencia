class GestorIndividualGerenciado < ApplicationRecord
  # Join table: um GestorIndividual gerencia N Users (frequentadores).
  belongs_to :gestor_individual
  belongs_to :user
end
